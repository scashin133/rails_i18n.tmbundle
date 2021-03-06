# encoding: UTF-8

# puts RUBY_VERSION

if RUBY_VERSION > "1.9"
  Encoding.default_external = Encoding::UTF_8
  # Encoding.default_internal = Encoding::UTF_8
else
  $KCODE = 'UTF8'
end

require ENV["TM_BUNDLE_SUPPORT"] + "/lib/text_mate"
require 'rubygems'
require 'yaml'
require 'active_support'
require 'ya2yaml'
require ENV["TM_BUNDLE_SUPPORT"] + "/lib/translator"
require ENV["TM_BUNDLE_SUPPORT"] + "/lib/bundle_config"
require ENV["TM_BUNDLE_SUPPORT"] + "/lib/gengo_lib/my_gengo"

# exit




class TranslateStrings
  def initialize
    check_requirements
    
    @translate_to = TextMate.input('Please enter the locale you want to auto-translate to (existing strings will not be overwritten)', '')
    
    if !@translate_to || @translate_to.strip == ''
      return
    else
      @translate_to = @translate_to.downcase
    end
    
    @translate_via = TextMate.choose('Choose how you want to translate the english locale?', ['Google Translate', 'MyGengo - Standard', 'MyGengo - Pro', 'MyGengo - Ultra'])
    
    if @translate_via != 0
      # Use MyGengo
      # Ask for API_KEYS if we haven't set them up yet
      if !$mygengo_api_key || !$mygengo_private_key || $mygengo_api_key.strip == '' || $mygengo_private_key.strip == ''
        BUNDLE_CONFIG.setup_keys
        return
      end
      
      # Confirm
      if !TextMate.message_yes_no_cancel("Are you sure?  This will cost money.")
        return
      end
    end

    default_locale = YAML::load(File.open($default_locale_file).read)[$default_locale]
    to_file = File.join(ENV['TM_PROJECT_DIRECTORY'], "config/locales/#{@translate_to}.yml")

    # Create blank file if it doesn't exist
    if !File.exists?(to_file)
      File.open(to_file, 'w') do |f|
        f.write(@translate_to + ":\n")
      end
    end

    # Load up the new file
    begin
      to_locale = YAML::load(File.open(to_file).read)[@translate_to] || {}
    rescue
      to_locale = {}
    end
    
    
    process(default_locale, to_locale, @translate_to)

    File.open(to_file, 'w') do |f|
      f.write({@translate_to => to_locale}.ya2yaml)
    end

  end
  
  def check_requirements
    # Check for httparty
    begin
      require "httparty"
    rescue
      TextMate.message("Please install the httpparty gem to use this bundle -- sudo gem install httparty")
      TextMate.exit_discard
      exit
    end
  end
  
  # Do the actual translating, or setup the placeholder
  def translate_string(string, from_locale, to_locale)
    if @translate_via.to_i == 0
      # Change {{token}} to __token__ so it won't be replaced
      tokened_value = string.gsub(/\{\{([^\}]+)\}\}/, '__\1__')

      string = Translator.translate(tokened_value, from_locale, to_locale)

      # Change back
      string = string.gsub(/__(.*?)__/, '{{\1}}')
      
      return string
    else
      # Via MyGengo
      if !defined?(@auto_approve)
        @auto_approve = TextMate.message_yes_no_cancel('Do you want MyGengo jobs to be auto-approved?')
      end
      
      mygengo = MyGengo.new($mygengo_api_key, $mygengo_private_key)
      
      
      tier = case @translate_via
      when 1
        'standard'
      when 2
        'pro'
      when 3
        'ultra'
      else
        return string
      end
      
      # play around with different parameter values to see their effect
      job = {
          'slug' => string.gsub(/\{\{([^\}]+)\}\}/, '[[[\1]]]'),
          'body_src' => string,
          'lc_src' => from_locale,
          'lc_tgt' => to_locale,
          'tier' => tier,
          'auto_approve' => @auto_approve
      }


      # place the full list of parameters relevant to this call in an array
      data = {'job' => job }

      resp = mygengo.create_job(data)
      begin
        return "___WAITING_JOB:#{resp['response']['job']['job_id']}___"
      rescue
        require 'cgi'
        TextMate.textbox("An error happened while translating, the following was returned", resp.inspect.gsub(/[\'\"\$]/, ''))
        return string
      end
    end
  end

  # Loop through the default locale and translate everything into the new locale
  # Skip if the translated version exists in the new locale
  def process(from_obj, to_obj, translate_to)
    if from_obj.is_a?(Hash)
      from_obj.each do |key,value|
        if value.is_a?(String)
          if !to_obj[key]
            string = translate_string(value, $default_locale, translate_to)

            to_obj[key] = string
          end
        else
          to_obj[key] ||= {}
          process(value, to_obj[key], translate_to)
        end
      end
    end
  end
end

TranslateStrings.new