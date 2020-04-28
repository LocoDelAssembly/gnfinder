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

    def self.find_names_json(text, opts = {})
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

      output
    end

    def self.find_names_hash(text, opts = {})
      find_names_converted(text, { klass: Hash, delete: :delete }, opts)
    end

    def self.find_names(text, opts = {})
      find_names_converted(text, { klass: OpenStruct, delete: :delete_field }, opts)
    end

    private

    def self.find_names_converted(text, container, opts = {})
      if output = find_names_json(text, opts)
        output = JSON.parse(output)
        output["metadata"].each_pair { |k, v| output[k] = v }
        output.delete("metadata")

        output = convert_snake_case(output, container[:klass])

        if output["total_words"]
          output["total_tokens"] = output["total_words"]
          output.send(container[:delete], "total_words")
        end

        output["names"] ||= []
        output["names"].each do |name|
          [%w[start offset_start], %w[end offset_end], %w[annotation_nomen annot_nomen], %w[annotation_nomen_type annot_nomen_type]].each do |pair|
            if name[pair[0]]
              name[pair[1]] = name[pair[0]]
              name.send(container[:delete], pair[0])
            end
          end

          name["odds"] ||= 0.0
          name["offset_start"] ||=  0
          name["offset_end"] ||=  0
          name["annot_nomen_type"] = name["annot_nomen_type"].to_sym if name["annot_nomen_type"]

          best_result = name.dig(:verification, :best_result)

          if best_result
            best_result.match_type = getMatchType(best_result.match_type)

            if best_result["classification_i_ds"]
              best_result["classification_ids"] = best_result["classification_i_ds"]
              best_result.send(container[:delete], "classification_i_ds")
            end
          end
        end
      end

      output
    end

    def self.convert_snake_case(hash, klass)
      res = klass.new

      hash.each do |key, value|
        str = key.gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
        str.gsub!(/([a-z\d])([A-Z])/, '\1_\2')
        str.downcase!

        if value.kind_of?(Hash)
          value = convert_snake_case(value, klass)
        elsif value.kind_of?(Array)
          value = value.map { |v| v.kind_of?(Hash) ? convert_snake_case(v, klass) : v  }
        end

        res[str] =  value
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
