CitrineApp::Application.routes.draw do
  get 'units/si' => 'si#convert'
end
