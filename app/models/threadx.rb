class Threadx < ActiveRecord::Base

	DEFAULT_COMPOSITE_IMAGE_WIDTH = 970

	MAX_IMAGES = 500
	MAX_DAYS = 186

	self.per_page = 20

	has_many :media_threadxes
	has_many :media, :through => :media_threadxes

	belongs_to :owner, :class_name => "User"

	has_many :threadx_collaborators
	has_many :collaborators, :through => :threadx_collaborators, :source => :user

	has_many :codes
	has_many :highlighted_areas, :through => :codes
	
	has_many :coded_pages

	validates :thread_name, :thread_display_name, :start_date, :end_date, :description , :category, :presence => true
	
	# this validation runs when a user create a thread, and checks if the user has a thread with same name or not
	validate :existing_thread, :on => :create

	validate :not_too_many_images
	
	validate :starts_before_ends

	validates :thread_name, :uniqueness=>true

	before_validation { |t| 
		t.thread_name = t.thread_display_name if t.thread_name.nil? or t.thread_name.empty?
		t.thread_name = t.thread_name.to_url 
	}

	# remove the generated composite images when a thread is changed
	after_save { |t| 
		t.remove_composite_images
	}

	# for now, default to sort by most recent first
	default_scope order('created_at DESC')

	def link_url
		'/'+owner.username.split(' ').join('_')+'/'+thread_name+'/'
	end

	def starts_before_ends
		if end_date < start_date
			errors.add(:end_date, 'must be after start date')
		end 
	end

	# workaround for bug #59: too big threads
	def not_too_many_images
		media_count = media.length
		days = end_date - start_date
		number_of_images = media_count * days
		if ((media_count * days) > MAX_IMAGES)
			errors.add(:start_date, "This range is too big.  Your number of total images must be below " + MAX_IMAGES.to_s + ". Your thread has now " + number_of_images.to_i.to_s + " images ( "+ days.to_i.to_s + " days * " + media_count.to_s + " newspapers). Make a shorter range or use less newspapers.")
		end
		if days > MAX_DAYS
			errors.add(:start_date, "This range is too big.  Your total number of days must be less than #{MAX_DAYS}")
		end
	end

	#returns the ids of images that are not coded
	def uncoded_image_ids
		all_img_ids = self.images.collect {|img| img.id }
		all_img_ids - coded_image_ids
	end

	#returns the ids of images that are coded: with highlighted areas or selected as "nothing to code"
	def coded_image_ids
		coded_img_ids = self.coded_pages.collect {|cp| cp.image_id }
		highlighted_img_ids = self.highlighted_areas.collect {|ha| ha.image_id}
		coded_img_ids + highlighted_img_ids
	end

	def existing_thread
		current_user = User.find owner_id
		thread = current_user.owned_threads.find_by_thread_display_name thread_display_name
		existed_thread = ( thread == nil )
		unless existed_thread
			unless thread.thread_name == nil
				errors.add(:thread_display_name, " There's already another thread with this name.")
			end
		end
	end
	
	def width
		return self.size.split('x')[0].to_f
	end

	def height
		return self.size.split('x')[1].to_f
	end

	# return an array of categories
	def category_list
		self.category.split(",")
	end

	def composite_image_map_info width=DEFAULT_COMPOSITE_IMAGE_WIDTH
		thread_img_dir = self.composite_img_dir width
		path = File.join(thread_img_dir, 'image_map.json')
		return nil unless File.exists? path
		JSON.parse( IO.read path )
	end

	def path_to_composite_cover_image width=DEFAULT_COMPOSITE_IMAGE_WIDTH
		File.join('threads',self.owner.id.to_s,self.id.to_s, width.to_s, 'front_pages.jpg').to_s
	end

	#returns the path of the image of highlighted areas from a code 
	def path_to_composite_highlighed_area_image code_id, width=DEFAULT_COMPOSITE_IMAGE_WIDTH
		File.join('threads',self.owner.id.to_s,self.id.to_s, width.to_s, 'code_'+code_id.to_s+'_overlay.png').to_s
	end

	def remove_composite_images width=DEFAULT_COMPOSITE_IMAGE_WIDTH
		logger.info "Removing composite images for '#{self.thread_name}' (#{self.id}) at #{self.composite_img_dir(width)}px"
		FileUtils.rm_r self.composite_img_dir(width) if Dir.exists? self.composite_img_dir(width) 
	end

	def scrape_all_images force_redownload=false
		KioskoScraper.create_images(self.start_date, self.end_date, self.media)
		if force_redownload
			self.images.each do |image|
    			image.download
	    		image.save
			end
		end
		remove_composite_images
	end

	# this passes info into the ImageCompositor so this code is a bit cleaner
	def generate_composite_images width=DEFAULT_COMPOSITE_IMAGE_WIDTH, force=false

		# bail if we've already done this
		thread_img_dir = self.composite_img_dir width
		return if not force and Dir.exists? thread_img_dir and File.exists? File.join(thread_img_dir, 'front_pages.jpg')

		logger.info "Creating composites for '#{self.thread_name}' (#{self.id}) at #{self.composite_img_dir(width)}px"

		# create the container dir
		self.composite_img_dir width, true
		FileUtils.mkpath self.composite_img_dir(width.to_s)

		# set up the copositing engine
		compositor = ImageCompositor.new self.start_date, self.end_date
		compositor.image_dir = self.composite_img_dir width
		compositor.width = width
		compositor.uncoded_image_ids = self.uncoded_image_ids

		# figure out each row height
		logger.info "  determining row heights"
		thumbnails = []
		self.media.each_with_index do |media, index|
			media_images = self.images.select { |img| img.media_id==media.id }
			thumbnail_media_heights = media_images.collect do |img| 
				img.image_height_at_width compositor.thumb_width
			end
			compositor.set_media_info(media.id, media.name_with_country, thumbnail_media_heights.max.round)
		end
		compositor.calculate_image_map_width_height

		# create the background image grid
		logger.info "  creating background image grid"
		compositor.generate_front_page_composite self.images

		# create an overlay and composite for each topic
		logger.info "  creating overlays for topics"
		full_ha_list = self.highlighted_areas.all
		self.codes.each do |code|
			code_highlisted_areas = full_ha_list.select { |ha| ha.code_id==code.id }
			compositor.generate_code_overlay_composite self.images, code_highlisted_areas, code.id, code.color
			compositor.generate_code_composite code.id
		end

		# combine into the total composite
		logger.info "  combining into composites"
		code_id_list = self.codes.collect { |code| code.id }
		compositor.generate_full_composite code_id_list
		compositor.generate_image_map
		compositor.generate_image_archive code_id_list

		logger.info "  done"

	end

	# length of threadx in days
	def duration
	 (end_date - start_date).to_i + 1   # plus one is because date range for threadx is inclusive
	end
	
	def images
		Image.by_media(medium_ids).by_date(start_date..end_date)
	end

	def non_missing_images(count)
		self.images.where(:missing=>false).limit(count)
	end

	def images_by_date
		Image.by_date(start_date..end_date).by_media(medium_ids)
	end

	def highlighted_areas_for_image(image)
		HighlightedArea.by_threadx(self).by_image(image)
	end
	
	def image_coded?(image)
		area_count = HighlightedArea.by_threadx(self).by_image(image).length
		skipped = coded_pages.for_image(image).length
		area_count > 0 or skipped > 0
	end
	
	def results(type = :tree)
		# Create an ordered list of newspapers, codes, dates
		res = {
			:media => media.map {|m| m.display_name},
			:codes => codes.map {|c| c.code_text},
			:dates => start_date .. end_date,
			:colors => {},
			:data => {}
		}
		codes.each do |c|
			res[:colors][c.code_text] = c.color
		end
		tree_data = {}
		flat_data = []
		# preload some data for better querying
		all_images = self.images.codeable.all
		all_ha_list = self.highlighted_areas.all
		# Create a tree: date->media->code->percentage
		(start_date..end_date).each do |date|
			media_code = {}
			# Initialize totals
			code_sum = {}
			code_count = 0.0
			codes.each do |code|
				code_sum[code.code_text] = 0.0
			end
			day_images = all_images.select { |img| img.publication_date==date}

			image_count = day_images.length
			# Caclulate percentage for each newspaper
			media.each do |m|
				media_day_images = day_images.select { |img| img.media_id==m.id}
				next if media_day_images.length == 0
				image = media_day_images.first # there should only really be one
				code_percent = {} 
				codes.each do |code|
					image_code_ha_list = all_ha_list.select { |ha| ha.image_id==image.id and ha.code_id==code.id}
					highlighted = image_code_ha_list.inject(0) { |area, ha| area + ha.area }
					percent = highlighted.to_f / (image.width * image.height)
					code_percent[code.code_text] = percent
					code_sum[code.code_text] += percent
					flat_data << {
						:id => "#{date}:#{m.display_name}:#{code.code_text}", :date => date, :media => m.display_name, :country => m.country, :code => code.code_text, :percent => percent, :image_count => image_count
					}
				end
				media_code[m.display_name] = code_percent
				code_count += 1.0
			end
			# Calculate totals
			code_percent = {}
			codes.each do |code|
				if code_count > 0
					code_percent[code.code_text] = code_sum[code.code_text] / code_count
				elsif
					code_percent[code.code_text] = 0.0
				end
			end
			media_code['Total'] = code_percent
			tree_data[date] = media_code
		end
		if type == :tree
			res[:data] = tree_data
		elsif type == :flat
			res[:data] = flat_data
		end
		return res
	end
	
	def composite_img_dir width=DEFAULT_COMPOSITE_IMAGE_WIDTH, create_dir=false
		dir = File.join('app','assets','images','threads',self.owner.id.to_s,self.id.to_s, width.to_s)
		if create_dir and not File.directory? dir
			FileUtils.mkpath dir
		end
		dir
	end
	
	def allowed_to_code?(user)
		return !user.nil? && (self.owner.id == user.id || !self.collaborators.find_by_id(user.id).nil? || user.admin)		
	end

end
