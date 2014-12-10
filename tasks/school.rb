namespace :poi do

  # crawl elementary schools
  task :update_elementary_schools do 
    update_school(::Db::BaseElementarySchool, 'Elementary')
  end

  # crawl middle schools
  task :update_middle_schools do 
    update_school(::Db::BaseMiddleSchool, 'Middle')
  end

  # crawl high schools
  task :update_high_schools do 
    update_school(::Db::BaseHighSchool, 'High')
  end
  
  def call( type )
    eval "::POI::School::#{type}"
  end

  def update_school( base, type )
    # todo: dynamic call
    num_of_page = call(type).max_page_num

    thread_num = 5
    queue = Queue.new
    works = num_of_page

    workers = (0..thread_num).map do 
      # start a new thread
      Thread.new do
        begin 
          while true
            # each thread deal with one page
            page_i = works
            works -= 1 
            p page_i
            raise "Works finished" if works < 0
            # sleep for 0.1 second
            sleep( 0.1 )

            begin # parse schools in one page and store into database
              schools = call(type).schools_in_page( page_i )
              schools.each do | school |
                queue.push( call(type).get_info( school ))
              end 
            rescue => e
              puts "error encountered when processing page: " + page_i.to_s
              p e
            end
          end
        rescue ThreadError
        end
      end 
    end # works.map

    # writer thread
    writer = Thread.new do
      # wait for workers
      sleep( thread_num*0.2 + 5 )
      while queue.length>0
        begin
          # shading use :master to write
          base.using(:master).new( queue.pop ).save    
        rescue => e
          p e
          # todo: add error handling
        end
        # adaptive wrting rate
        sleep( 1.0/(queue.length+1) )
      end
    end

    # hold main thread 
    workers.map(&:join); 
    writer.join
  end

end