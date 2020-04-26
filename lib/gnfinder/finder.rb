# frozen_string_literal: true

module Gnfinder
  # Parser provides a namespace for functions to parse scientific names.
  module Finder
    extend FFI::Library

    platform = case Gem.platforms[1].os
               when 'linux'
                 'linux'
               when 'darwin'
                 'mac'
               when 'mingw32'
                 'win'
               else
                 raise "Unsupported platform: #{Gem.platforms[1].os}"
               end
    ffi_lib File.join(__dir__, '..', '..', 'clib', platform, 'libgnfinder.so')
    POINTER_SIZE = FFI.type_size(:pointer)

    callback(:parser_callback, %i[string], :void)

    attach_function(:find_go, :FindNamesToJSON,
                    %i[string string parser_callback], :void)

    def self.find_names(text, opts = {})
      params = {}
      params[:no_bayes] = true if opts[:no_bayes]
      params[:language] = opts[:language] if opts[:language].to_s.strip != ''
      if opts[:detect_language]
        params[:detect_language] = opts[:detect_language]
      end
      params[:verification] = true if opts[:verification]
      if opts[:sources] && !opts[:sources].empty?
        params[:sources] = opts[:sources]
      end

      if opts[:tokens_around] && opts[:tokens_around] > 0
          params[:tokens_around] = opts[:tokens_around]
      end

      output = nil
      callback = FFI::Function.new(:void, [:string]) { |str| output = str }
      find_go(text, params.to_json, callback)

      if output
        output = JSON.parse(output)
        output["metadata"].each_pair { |k, v| output[k] = v }
        output.delete("metadata")

        output = convert_snake_case(output)
        if output.total_words
          output.total_tokens = output.total_words
          output.delete_field("total_words")
        end

        output.names ||= []
        output.names.each do |name| 
          [%w[start offset_start], %w[end offset_end], %w[annotation_nomen annot_nomen], %w[annotation_nomen_type annot_nomen_type]].each do |pair|
            if name[pair[0]]
              name[pair[1]] = name[pair[0]]
              name.delete_field(pair[0])
            end
          end

          name.odds ||= 0.0
          name.offset_start ||=  0
          name.offset_end ||=  0
          name.annot_nomen_type = name.annot_nomen_type.to_sym if name.annot_nomen_type

          best_result = name.dig(:verification, :best_result)

          if best_result
            best_result.match_type = getMatchType(best_result.match_type)
          end
        end
      end

      output
    end

    private

    def self.convert_snake_case(hash)
      res = OpenStruct.new

      hash.each do |key, value|
        str = key.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
        str.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
        str.downcase!

        if value.kind_of?(Hash)
          value = convert_snake_case(value)
        elsif value.kind_of?(Array)
          value = value.map { |v| v.kind_of?(Hash) ? convert_snake_case(v) : v  }
        end

        res[str.to_sym] =  value
      end

      res
    end

    def self.getMatchType(match)
      case match
      when "ExactMatch"
        return :EXACT
      when "ExactCanonicalMatch"
        return :EXACT
      when "FuzzyCanonicalMatch"
        return :FUZZY
      when "ExactPartialMatch"
        return :PARTIAL_EXACT
      when "FuzzyPartialMatch"
        return :PARTIAL_FUZZY
      else
        return :NONE
      end
    end
    
  end
end
