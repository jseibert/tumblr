module Tumblr
  class Post
    attr_reader :postid, :url, :date, :bookmarklet
    
    # works just like ActiveRecord's find. (:all, :first, :last or id)
    def self.find(*args)
      options = args.extract_options!
      
      if((user = args.second).is_a?(Tumblr::User))        
        options = options.merge(
          :email =>     user.email,
          :password =>  user.password
        )        
      end
          
      doc = REXML::Document.new(case args.first
        when :first then find_initial(options)
        when :last  then find_last(options)
        when :all   then find_every(options)
        else             find_from_id(args.first, options)
      end)
      
      tumblelog = Tumblelog.new(REXML::XPath.first(doc, "//tumblelog"))
      posts = Posts.new(REXML::XPath.first(doc, "//posts"), tumblelog.timezone)
      return posts[0] if args.first != :all
      posts
    end
  
    # find the first post
    def self.find_initial(options)
      Tumblr::Request.read(options.merge(:start => 0, :num => 1))
    end
  
    # find the last post
    def self.find_last(options)
      total = all['tumblr']['posts']['total'].to_i
      Tumblr::Request.read(options.merge(:start => total - 1, :num => 1))
    end
    
    # find all posts (the maximum amount of posts is 50, don't blame the messenger)
    def self.find_every(options)
      Tumblr::Request.read(options.merge(:num => 50))
    end
  
    # find a post by id
    def self.find_from_id(id, options)
      Tumblr::Request.read(options.merge(:id => id))
    end
  
    # alias of find(:all)
    def self.all(*args)
      self.find(:all, *args)
    end
    
    # alias of find(:first)
    def self.first(*args)
      self.find(:first, *args)
    end    
    
    # alias of find(:last)
    def self.last(*args)
      self.find(:last, *args)
    end
    
    # create a new post
    def self.create(*args)
      options = process_options(*args)
      Tumblr::Request.write(options)
    end
    
    # update a post
    def self.update(*args)
      options = process_options(*args)
      Tumblr::Request.write(options)
    end
    
    # destroy a post
    def self.destroy(*args)
      options = process_options(*args)
      Tumblr::Request.delete(options)
    end
    
    # extracts options from the arguments, converts a user object to :email and :password params and fixes the :post_id/'post-id' issue.
    def self.process_options(*args)
      options = args.extract_options!

      if((user = args.first).is_a?(Tumblr::User))        
        options = options.merge(
          :email =>     user.email,
          :password =>  user.password
        )
      end
            
      if(options[:post_id])
        options['post-id'] = options[:post_id]
        options[:post_id] = nil
      end
      
      return options
    end

    def initialize(elt, tz)
      @postid = elt.attributes["id"]
      @url = elt.attributes["url"]
      @date = Time.parse(elt.attributes["date"] + tz.strftime("%Z"))
      @bookmarklet = (elt.attributes["bookmarklet"] == "true")
      @timezone = tz
    end

    def to_xml
      elt = REXML::Element.new("post")
      elt.attributes["id"] = @postid
      elt.attributes["date"] = @date.strftime("%a, %d %b %Y %X")
      elt.attributes["bookmarklet"] = "true" if @bookmarklet
      elt.attributes["url"] = @url
      return elt
    end
  end
  
  class Tumblelog
    attr_accessor :name, :timezone, :cname, :title, :description

    def initialize(elt)
      @name = elt.attributes["name"]
      @timezone = TZInfo::Timezone.get(elt.attributes["timezone"])
      @cname = elt.attributes["cname"]
      @title = elt.attributes["title"]
      @description = elt.text
    end

    def to_xml
      elt = REXML::Element.new("tumblelog")
      elt.attributes["name"] = @name
      elt.attributes["timezone"] = @timezone.name
      elt.attributes["cname"] = @cname
      elt.attributes["title"] = @title
      elt.text = @description
      return elt
    end
  end
  
  class Posts < Array
    attr_accessor :total, :start, :type

    def initialize(elt, tz)
      @total = elt.attributes["total"].to_i
      @start = elt.attributes["start"].to_i if elt.attributes.has_key? "start"
      @type = elt.attributes["type"]

      elt.elements.each("post") do |e|
        push((case e.attributes["type"]
         when "regular"; Regular
         when "quote"; Quote
         when "photo"; Photo
         when "link"; Link
         when "video"; Video
         when "conversation"; Conversation
        end).new(e, tz))
      end
    end

    def to_xml
      elt = REXML::Element.new("posts")
      elt.attributes["total"] = @total
      elt.attributes["type"] = @type
      each do |post|
        elt.elements << post.to_xml
      end
      return elt
    end
  end

  class Regular < Post
    attr_accessor :title, :body

    def initialize(elt, tz)
      super
      if elt.elements["regular-title"]
        @title = elt.elements["regular-title"].text
      end
      if elt.elements["regular-body"]
        @body = elt.elements["regular-body"].text
      end
    end

    def to_xml
      elt = super
      elt.attributes["type"] = "regular"
      if @title
        (elt.add_element("regular-title")).text = @title
      end
      if @body
        (elt.add_element("regular-body")).text = @body
      end
      return elt
    end
    
    def to_s
      @title
    end
  end

  class Quote < Post
    attr_accessor :text, :source

    def initialize(elt, tz)
      super
      @text = elt.elements["quote-text"].text
      if elt.elements["quote-source"]
        @source = elt.elements["quote-source"].text
      end
    end

    def to_xml
      elt = super
      elt.attributes["type"] = "quote"
      et = elt.add_element("quote-text")
      et.text = @text
      if @source
        (elt.add_element("quote-source")).text = @source
      end
      return elt
    end
  end

  class Photo < Post
    attr_accessor :caption, :urls

    def initialize(elt, tz)
      super
      if elt.elements["photo-caption"]
        @caption = elt.elements["photo-caption"].text
      end
      @urls = Hash.new
      elt.elements.each("photo-url") do |url|
        @urls[url.attributes["max-width"].to_i] = url.text
      end
    end

    def to_xml
      elt = super
      elt.attributes["type"] = "photo"
      if @caption
        (elt.add_element "photo-caption").text = @caption
      end
      @urls.each do |width, url|
        e = elt.add_element "photo-url", {"max-width" => width}
        e.text = url
      end
      return elt
    end
    
    def title
      parts = caption.split("\n", 2)
      title = parts[0]
      if parts[1] && title && title.length < 90
        return title
      end
      
      nil
    end
    
    def body
      title ? caption.split("\n", 2)[1] : caption
    end
  end

  class Link < Post
    attr_accessor :name, :url, :description

    def initialize(elt, tz)
      super
      @text = elt.elements["link-text"].text if elt.elements["link-text"]
      @url = elt.elements["link-url"].text
      @description = elt.elements["link-description"].text if elt.elements["link-description"]
    end

    def to_xml
      elt = super
      elt.attributes["type"] = "link"
      name = elt.add_element "link-text"
      name.text = @text
      url = elt.add_element "link-url"
      url.text = @url
      description = elt.add_element "link-description"
      description.text = @description
      return elt
    end
  end

  class Conversation < Post
    attr_accessor :title, :lines

    def initialize(elt, tz)
      super
      if elt.elements["conversation-title"]
        @title = elt.elements["conversation-title"]
      end
      @text = elt.elements["conversation-text"].text
      @lines = []
      elt.elements.each("conversation-line") do |line|
        name = line.attributes["name"]
        label = line.attributes["label"]
        @lines << [name, label, line.text]
      end
    end

    def to_xml
      elt = super
      elt.attributes["type"] = "conversation"
      if @title
        (elt.add_element "conversation-title").text = @title
      end
      text = elt.add_element "conversation-text"
      text.text = @text
      @lines.each do |line|
        e = elt.add_element "conversation-line", {"name" => line[0], "label" => line[1]}
        e.text = line[2]
      end
      return elt
    end
  end

  class Video < Post
    attr_accessor :caption
    
    def initialize(elt, tz)
      super
      @caption = elt.elements["video-caption"].text
      @source = elt.elements["video-source"].text
      @player = elt.elements["video-player"].text
    end

    def to_xml
      elt = super
      elt.attributes["type"] = "video"
      caption = elt.add_element "video-caption"
      caption.text = @caption
      player = elt.add_element "video-player"
      player.text = @player
      source = elt.add_element "video-source"
      source.text = @source
      return elt
    end
    
    def title
      parts = caption.split("\n", 2)
      title = parts[0]
      if parts[1] && title && title.length < 90
        return title
      end
      
      nil
    end
    
    def body
      title ? caption.split("\n", 2)[1] : caption
    end
  end
end

