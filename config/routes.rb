Pageonex::Application.routes.draw do
  devise_for :users
  resources :users

  match 'threads/mine' => 'threads#mine'
  match 'threads/by/:username' => 'threads#by_username'
  match 'threads/search' => 'threads#search'
  match 'threads/search_by_category' => 'threads#search_by_category'
  match 'threads/new_topic/:index' => 'threads#new_topic'
  resources :threads

  match 'images/download' => 'images#download'
  match 'images/for_media/:media_id' => 'images#for_media'
  resources :images

  resources :media

  match ':username/:thread_name/export' => 'threads#export'
  match ':username/:thread_name/coding' => 'coding#process_images'
  match ':username/:thread_name/process_highlighted_areas' => 'coding#process_highlighted_areas'
  match ':username/:thread_name' => 'coding#display'
  match ':username/:thread_name/embed' => 'coding#embed'

  match '/about' => 'home#about'
  match '/help' => 'home#help'
  match '/terms-of-service' => 'home#terms-of-service'
  match '/privacy-policy' => 'home#privacy-policy'
  match '/export_chart' => 'home#export_chart'

  root :to => "home#index"



  # The priority is based upon order of creation:
  # first created -> highest priority.

  # Sample of regular route:
  #   match 'products/:id' => 'catalog#view'
  # Keep in mind you can assign values other than :controller and :action

  # Sample of named route:
  #   match 'products/:id/purchase' => 'catalog#purchase', :as => :purchase
  # This route can be invoked with purchase_url(:id => product.id)

  # Sample resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Sample resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Sample resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Sample resource route with more complex sub-resources
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', :on => :collection
  #     end
  #   end

  # Sample resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end

  # You can have the root of your site routed with "root"
  # just remember to delete public/index.html.
  # root :to => 'welcome#index'

  # See how all your routes lay out with "rake routes"

  # This is a legacy wild controller route that's not recommended for RESTful applications.
  # Note: This route will make all actions in every controller accessible via GET requests.
  # match ':controller(/:action(/:id))(.:format)'
end
