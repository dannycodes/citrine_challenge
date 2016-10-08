class SiConverterService
	# Define Operator Characters
	OPEN_PAREN = "("
	CLOSE_PAREN = ")"
	MULTIPLY = "*" 	
	DIVIDE = "/"

	# Describe given table as constants (see Citrine problem primer)
	MINUTE = {si_unit: "s", multiplier: 60.to_f.round(14)}
	HOUR = {si_unit: "s", multiplier: 3600.to_f.round(14)}
	DAY = {si_unit: "s", multiplier: 86400.to_f.round(14)}
	DEGREE = {si_unit: "rad", multiplier: (Math::PI / 180).round(14)}
	ARCMINUTE = {si_unit: "rad", multiplier: (Math::PI / 10800).round(14)}
	ARCSECOND = {si_unit: "rad", multiplier: (Math::PI / 648000).round(14)}
	AREA = {si_unit: 0x006d.chr(Encoding::UTF_8) + 0x00b2.chr(Encoding::UTF_8), 
			multiplier: 10000.round(14)}
	VOLUME = {si_unit: 0x006d.chr(Encoding::UTF_8) + 0x00b3.chr(Encoding::UTF_8),
			multiplier: 0.001.round(14)}
	MASS = {si_unit: "kg", multiplier: 1000}

	# Describe SI/lay-unit relationship (see Citrine problem primer)
	SI_RELATIONSHIPS = {
		"minute" => MINUTE, 
		"min" => MINUTE, 
		"hour" => HOUR,
		"h" => HOUR, 
		"day" => DAY, 
		"d" => DAY, 
		"degree" => DEGREE, 
		0x00b0 => DEGREE,
		0x0027 => ARCMINUTE, 
		0x0022 => ARCSECOND, 
		"hectare" => AREA, 
		"ha" => AREA, 
		"litre" => VOLUME, 
		"L" => VOLUME,
		"tonne" => MASS, 
		"t" => MASS
	}

	class << self 

		### Dirty Explanation
		# 1. Split input into arguments (i.e. 'degree' or 'minute') by operators ('*', '/', '(', ')')
		#    a. determine where parenthesis lie (this allows the calculation of 'depth'. See point 2)
		#    b. split on operator characters
		# 	 c. attribute appropriate operator to each argument
		# 2. Create data objects (see build_arguments method) 
		#    to contain data from mapping, location, operator, and 'depth' (if nested in parenthesis)
		# 	 If nested in parenthesis, assigned value from 0 to n. Otherwise -1 (outside all parenthesis)
		# 3. Group arguments by which parenthesis they are in, if any. If in parenthesis, do a loop which
		# 	 a. calculates multiplier for arguments in that parenthesis, 
		#    b. computes what the new name should be
		#    c. adds parenthesis
		#    Then return the new argument, which is the 'calculated' old argument
		# 4. Now everything is top-layer (out of parenthesis, since we've done the nested calculations)
		#    We thus run the same processing loop as in point 3, but we don't add parenthesis
		# 5. Clean answer and return

		def convert(input)
			# converts a non-si string of units into si units and a multiplier
			arguments = parse_input(input)
			output = run_calculation(arguments, input)
			{unit_name: output[:new_name], multiplier: output[:multiplier]}
		end

		def parse_input(input)
			# splits input by operator character
			# abstracts string into list of 'argument' objects
			current_chars = ""
			arguments = []
			parenthesis = extract_parenthesis(input)
			input.split("").each_with_index do |char, index|
				if char == OPEN_PAREN or char == CLOSE_PAREN or char == MULTIPLY or char == DIVIDE
					current_chars, arguments = build_arguments(input, arguments, current_chars, parenthesis, index, char)
				else
					current_chars += char 
				end
			end

			# Buffer either empty or has one argument 
			# process it, assign it a location of 'end of input', and give it nil as operator (no operator since last arg)
			current_chars, arguments = build_arguments(input, arguments, current_chars, parenthesis, input.length - 1, nil)
			return arguments
		end

		def build_arguments(input, arguments, current_chars, paren, index, char)
			# build an argument object
			return "", arguments if current_chars == ""

			# calculate depth as -1 unless current index in paren range
			# then assign depth 0..n
			depth = -1 
			paren.each_with_index do |p, _index| 
				depth = _index if p.include?(index)
			end

			# assign operator to argument
			# if char is close paren then use next char as operator
			operator = nil
			operator = input[index + 1] if char == CLOSE_PAREN
			operator = char if char == MULTIPLY or char == DIVIDE

			si_unit_info = get_si(current_chars)
			arguments << {	
				old_name: current_chars, 
				new_name: si_unit_info[:si_unit], 
				multiplier: si_unit_info[:multiplier], 
				depth: depth,
				location: index,
				operator: operator
			}
			current_chars = ""
			return current_chars, arguments
		end

		def get_si(non_si_unit)
			# Try ordinal if string doesn't return a value (could be ordinal input)
			si_hash = SI_RELATIONSHIPS[non_si_unit]
			si_hash = SI_RELATIONSHIPS[non_si_unit.ord] if si_hash.nil?
			si_hash
		end

		def extract_parenthesis(input)
			# Get the locations of each parenthesis in the input string
			# return list of indexes that are in parenthesis (endpoint inclusive)
			parenthesis = []
			input.split("").each_with_index do |char, index|
				if char == "("
					close = index
					input.split("")[index..-1].each_with_index do |_char, _index| 
						if _char == ")" 
							close = index + _index
							break
						end 
					end
					parenthesis << (index..close).to_a
				end
			end
			parenthesis
		end

		def run_calculation(arguments, input)
			# loop arguments objects, calculate multiplier, get new name
			top_level_arguments = []

			# Ignore depth == -1 here: only consider args in parenthesis in first pass
			# Deep copy arguments bc need it later
			arg_groups = Marshal.load(Marshal.dump(arguments)).select{|arg| arg[:depth] > -1}
			                                                  .group_by{|arg| arg[:depth]}.values
			arg_groups.each do |arg_group|
				output_arg = loop_arg_group(arg_group, true)
 				top_level_arguments << output_arg
			end

			# Add any arguments that were outside of parenthesis, if they exist
			orig_top_level_arguments = arguments.select{|arg| arg[:depth] == -1}
			top_level_arguments << orig_top_level_arguments if orig_top_level_arguments.present?
			# ensure correct operator (order matters)a
			top_level_arguments = top_level_arguments.flatten.sort_by{|arg| arg[:location]}
			loop_arg_group(top_level_arguments, false)
		end

		def loop_arg_group(arg_group, is_paren)
			# iterate through arguments in the same parenthetical group
			output_arg = {}
			last_arg = {}
			arg_group.sort_by{|arg| arg[:location]}.each_with_index do |arg, ind|
				if ind == 0
					output_arg = arg
					next
				end

				output_arg[:old_name] = output_arg[:old_name] + output_arg[:operator] + arg[:old_name]
				output_arg[:new_name] = output_arg[:new_name] + output_arg[:operator] + arg[:new_name]
				output_arg[:multiplier] = operate(output_arg[:operator], output_arg[:multiplier], arg[:multiplier])
				output_arg[:depth] = -1
				output_arg[:location] = [output_arg[:location], arg[:location]].min
				output_arg[:operator] = arg[:operator] # select the last argument
			end

			if is_paren
				output_arg[:old_name] = "(#{output_arg[:old_name]})"
				output_arg[:new_name] = "(#{output_arg[:new_name]})"
			end

			output_arg
		end

		def operate(operator, value1, value2)
			if operator == "*"
				value = value1 * value2
			elsif operator == "/"
				value = value1 / value2
			else 
				raise "Operator neither multiplication or division"
			end
			value
		end
	end
end
