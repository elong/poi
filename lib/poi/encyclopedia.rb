module Db
  class BasePoiEncyclopedia < ActiveRecord::Base
  end
  class BasePoiLandmark < ActiveRecord::Base
  end
end

module POI
  class Encyclopedia
    BASE_URL = 'http://www.baike.com/wiki/'
    REGEX    = /\s+|（.+）|( +)/

    def initialize
      @landmarks    =   Db::BasePoiLandmark
      @encyclopedia =   Db::BasePoiEncyclopedia
      @redis        =   Redis.new(:host=>"127.0.0.1", :port=>6379)
      @pipe         =   Queue.new
    end

   # Extract text from content
    def extract_text(doc=nil)
      return "" if doc.nil?
      doc.traverse { |node|  node.text.gsub(/\s|　/, "") }
    end
    
   # Process the landmark as keyword,for example:上海广场（原无限度）--> 上海广场,
    def url(landmark)
      keyword = landmark.gsub(REGEX,'')
      URI::encode "#{BASE_URL}#{keyword}"
    end

   # Logger
    def log(msg)
      log_file = File.open("log/encyclopedia.err", "a+")
      log_file.syswrite(msg)
      log_file.close
    end

   # Encyclopedia content of landmark
    def content(landmark)
      @html    = Nokogiri::HTML HTTParty.get(url(landmark)).body
      @content = @html.at("//div[@id='content']")
      return  if @content.nil?
      @summary = @html.at("//div[@class='summary']/p[text()!='']")
      if @summary.nil? or @summary.text.strip.size<100
        content_h2 = ''
        @content.search("p[text()!='']").each do |para|      
          content_h2 = extract_text(para)
          break if content_h2.size > 50
        end
        if content_h2==''
          @html.xpath("//div[@id='content']/text()").each do |para|
            content_h2 = para.text
            break if content_h2.size > 50
          end
        end
        extract_text(@summary)+content_h2
      else
        extract_text(@summary)
      end
    end
    
   # Fetch landmark from database and call function `content` to crawl encyclopedia content 
    def producer
      Thread.new { 
      start       =  get_rd('lm_time_sk')
      landmarks   =  @landmarks.where("updated_at>=?", start).order("id ASC")
      @all_amount = landmarks.size
      @timer, @counter =  Time.now, 0
      landmarks.find_each do |landmark|
        @landmark =  landmark
        limiter   =  0
        begin
          sleep(3*rand(0.0..1.0))  # change this if necessary
          elp_content = content(landmark[:name]) || content("#{landmark[:city_cn]}#{landmark[:name]}")
          encyclopedia =  {
            :name      => landmark[:name], 
            :city      => landmark[:city_cn],
            :content   => elp_content,
            }
          @pipe << encyclopedia
          @counter+=1
        rescue => e
          limiter+=1
          retry if limiter<3
          if e.message=="404 Not Found" or e.class==URI::InvalidURIError
            puts "#{landmark}"
            next
          else
            error_handler e
          end
        end
      end
      }
    end

   # Insert each row record into database
    def consumer
      Thread.new {
        while @pipe.size>0 or @pduer.status
          row     = @pipe.pop
          existed = @encyclopedia.find_by(name: row[:name], city: row[:city])
          existed.nil? ? @encyclopedia.new(row).save : existed.update(row)
          sleep(1/(@pipe.size+1))
        end
      }
    end

    def work
      begin
        @pduer  = producer
        @writer = consumer
        @pduer.join
        @writer.join
      rescue Exception=>e
        error_handler e
      end
      set_rd('lm_time_sk')
    end

    def error_handler(e, c=@counter, len=@all_amount)
      set_rd('lm_time_sk', @landmark[:updated_at])
      msg  = %Q(#{Time.now} #{e.class} #{e.message} finished: #{c}, unfinished: #{len-c}, timeleft: #{((Time.now-@timer)*len/c).to_i} seconds.\n)
      log(msg)
      warn @landmark[:name]
      raise e
    end

   # html content for debug purpose
    def html
      @html.to_html
    end

    def get_rd(key)
      value = @redis.get(key)
      value.nil? ? Time.at(0) : Time.parse(value)
    end

    def set_rd(key,value=0)
      @redis.set(key, Time.at(value))
    end

  end
end
