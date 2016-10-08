class SiController < ActionController::Base
	def convert
		input = params[:units]
		response = SiConverterService.convert(input)
		render json: response.to_json
	end
end