Shoes.setup do
  Gem.sources = ['http://gems.github.com/', 'http://gems.rubyforge.org/']
  gem 'minter-raccdoc'
end

require 'raccdoc'
require 'sqlite3'
require 'yaml/store'

class RaccdocClient < Shoes
  LICENSE = <<eof
Copyright 2009 Edward Heil ( edheil (at) fastmail (dot) fm )

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
eof

  HOST = '64.198.88.46' # bbs.iscabbs.com was not resolving
  PORT = 6145
  STACKSTYLE = { :margin => 20 }
  URLRE = Regexp.new('https?://[^ \n\)]+')
 
  url '/', :login
  url '/forums', :forums
  url '/goto/(\d+)', :goto
  url '/login', :login
  url '/license', :license
  url '/forum/(\d+)', :forum
  url '/foruminfo/(\d+)', :foruminfo
  url '/first_todo', :first_todo
  url '/first_unread/(\d+)', :first_unread
  url '/message/(\d+)/(\d+)/(.*)', :message
  url '/mark_unread/(\d+)/(\d+)', :mark_unread
  url '/new_post/(\d+)', :new_post
  url '/new_reply/(\d+)/(\d+)', :new_reply
  @@bbs, @msg_store = nil, nil
  @@forum_cache = {}
  @@msg_store = SQLite3::Database.new('messages.db')
  @@msg_store.execute("CREATE TABLE IF NOT EXISTS messages(forum_id INTEGER, message_id INTEGER, date TEXT, body TEXT, author TEXT, authority TEXT, UNIQUE (forum_id, message_id) ON CONFLICT REPLACE);");

  def license
    background black
    stack STACKSTYLE do
      background aliceblue, :curve => 20
      border black, :curve => 20
      para link('back', :click => '/login')
      para LICENSE
    end
  end

  def login
    background black
    @store = YAML::Store.new('bbsconfig.yaml')
    @username, @password = nil, nil
    @store.transaction(true) do
      @username, @password = @store['username'], @store['password']
    end

    def do_login
      @@username = @username_line.text
      @@password = @password_line.text
      @mainstack.append do
        para "logging in..."
      end
      Thread.new do
        begin
          @@bbs = Raccdoc::Connection.new(:user => @@username, :password => @@password,
                                          :host => HOST,
                                          :port => PORT
                                          )
        rescue RuntimeError => err
          debug "error: #{err.message}"
          @@bbs = nil
          @mainstack.append do
            para err.message
          end
        end
        if @@bbs
          @store.transaction do
            @store['username'], @store['password'] = @username, @password
          end
          visit '/forums'
        end
     end
    end


    @mainstack = stack STACKSTYLE do
      background salmon, :curve => 20
      border black, :curve => 20
      tagline "Login"
      para "username:"
      @username_line = edit_line "#{ @username }"
      para "password:"
      @password_line = edit_line "#{ @password }", :secret => true

      button "login" do
        do_login
      end

      para(link( 'license', :click => '/license' ))


      keypress do | key |
        if key == "\n"
          do_login
        end
      end
    end
  end

  def forums
    background black

    @mainstack = stack STACKSTYLE do
      background aliceblue, :curve => 20
      border black, :curve => 20
      para "loading forums..."
    end
    
    Thread.new do
      forums = @@bbs.forums('all')
      forums_todo = (@@bbs.forums('todo').to_a.map{ |k| k[0] } - [1]).sort
      forums_joined = (@@bbs.forums('joined').to_a.map{ |k| k[0]} - forums_todo - [1]).sort
      forums_all = (forums.to_a.map{ |k| k[0]} - forums_joined - forums_todo - [1]).sort
      forums_todo.each { |n| forums[n][:todo] = true }
      forums_joined.each { |n| forums[n][:joined] = true }
      # delete mail
      forums.delete(1)
      linklist, keypressproc = actions( [[ ' ', '[ ]first forum with unread', "/first_todo"],
                                         [ 'q', '[q]uit', Proc.new { exit() } ]
                                        ] )
      keypress { | key | keypressproc.call(key) }
      @mainstack.clear do
        background aliceblue, :curve => 20
        border black, :curve => 20
        para *linklist
        #  100 =>  { :topic => "100", :flags => 'nosubject,sparse,cananonymous', 
        #            :name => "Some Forum", :lastnote => "99999", :admin => "Some Dude" }
        [ ["Unread", forums_todo],
          ["Subscribed", forums_joined],
          ["Zapped", forums_all]].each do | pair |
          group_name, ordered_ids = *pair
          stack STACKSTYLE do
            background white, :curve => 20
            border black, :curve => 20
            caption group_name
            flow do
              ordered_ids.each do | id |
                data = forums[id]
                stack :width => 200, :margin => 20 do
                  if data[:todo]
                    background ivory, :curve => 10
                  elsif data[:joined]
                    background lightgrey, :curve => 10
                  else
                    background darkslateblue, :curve => 10
                  end
                  border black, :curve => 10
                  para link("#{id}> #{data[:name]}", :click => "/forum/#{id}")
                end
              end
            end
          end
        end
      end
    end
  end
  

  def goto(id)
    # id is forum to jump *from*
    id = id.to_i
    para "marking read, moving on..."
    Thread.new {
      @the_forum = @@bbs.jump(id)
      @the_forum.first_unread = @the_forum.noteids.sort.last.to_i + 1
      visit '/first_todo'
    }
  end

  def with_new_bbs_connection
    begin
    bbs = Raccdoc::Connection.new(:user => @@username, :password => @@password,
                                  :host => HOST,
                                  :port => PORT
                                  )
    yield bbs
      rescue RuntimeError => err
      debug "error: #{err.message}"
      visit '/'
    end
  end
  
  
  def sneakily_cache_forum(forum_id, note_ids)
    # if the main message db doesn't exist, don't bother making a new one
    return unless @@msg_store
    Thread.new {
      # this is a separate thread; we need our own bbs and db handle
      with_new_bbs_connection do | bbs |
        msg_store = SQLite3::Database.new('messages.db')
        sql = 'SELECT message_id FROM messages WHERE forum_id = ? AND message_id IN (' +
          Array.new(note_ids.length, '?').join(', ') +' ) ;'
        already_stored = msg_store.execute(sql, forum_id, *note_ids).flatten.map {|_|_.to_i}
        (note_ids - already_stored).each do | msgnum |
          get_message_from_bbs_and_store(forum_id, msgnum, bbs, msg_store)
        end
      end
    }
  end

  def forum(id)
    id = id.to_i
    background black
    
    @mainstack = stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "loading forum #{id}..."
    end


    Thread.new {
      @@forum_cache[id] = {}
      @forum = @@bbs.jump(id)
      first_unread = @forum.first_unread.to_i
      @@forum_cache[id][:first_unread] = first_unread
      @posts = @forum.post_headers
      noteids = @forum.noteids.sort
      @@forum_cache[id][:noteids] = noteids
      sneakily_cache_forum(id, noteids)
      @@forum_cache[id][:name] = @forum.name
      msgs_unread = noteids.select { |msg| msg.to_i >= first_unread }
      msgs_read = noteids.select { |msg| msg.to_i < first_unread }
      info "got posts"
    linklist, keypressproc = actions( [[ 'e', '[e]nter msg', "/new_post/#{id}"],
                                       [ 'i', '[i]nfo', "/foruminfo/#{id}"],
                                       [ 'l', 'forum [l]ist', "/forums"],
                                       [ 'f', 'read [f]orward', 
                                         "/message/#{id}/#{noteids.first}/forward"],
                                       [ 'b', 'read [b]ackward', 
                                         "/message/#{id}/#{noteids.last}/backward"],
                                       [ 'g', '[g]oto next forum with unread messages', 
                                         "/goto/#{id}"],
                                       [ ' ', '[ ]first unread', "/first_unread/#{id}"],
                                       [ 'q', '[q]uit', Proc.new { exit() } ]
                                      ] )
    
    keypress { | key |  keypressproc.call(key) }


      @mainstack.clear do
        background blanchedalmond, :curve => 20
        border black, :curve => 20

        para *linklist
        [ [ "Unread", msgs_unread,  ],
          [ "Read", msgs_read,  ]].each do | pair |
          group_name, ordered_ids = *pair
          info "adding #{group_name} stack"
          stack :margin => 20 do
            background white, :curve => 20
            border black, :curve => 20
            caption group_name
            flow do
              ordered_ids.reverse.each do | post_id |
                post = @posts[post_id.to_s]
                stack :margin => 20, :width => 200 do
                  background ivory, :curve => 10
                  border black, :curve => 10
                  para link("#{ post_id }/#{post[:author]}/#{post[:date]}/#{post[:size]}", :click => "/message/#{id}/#{post_id}/forward")
                  para post[:subject]
                end
              end
            end
          end
        end
      end
    }
  end
    
  def foruminfo(id)
    @forum = @@bbs.jump(id)
    background black
    
    linklist, keypressproc = actions [[ 'b', '[b]ack', "/forum/#{id}"],
                                      [ 'p', '[e]nter msg', "/new_post/#{id}"],
                                      [ " ", "[ ]first unread message", "/first_unread/#{id}" ],
                                      [ "q", "[q]uit", Proc.new { exit()} ]
                                     ]
    keypress { | key |  keypressproc.call(key) }
    
    stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para *linklist
      @info = @forum.forum_information
      the_body = @info[:body]
      body_urls = the_body.scan(URLRE)
      stack STACKSTYLE do
        background lightgrey, :curve => 10
        border black, :curve => 10
        caption "Forum moderator is #{@forum.admin}.  Total messages: #{@forum.noteids.last}."
        caption "Forum info last updated #{@info[:date]} by Mikemike"
        para "#{@info[:body]}"
        body_urls.each do | a_url |
          para link(a_url, :click => a_url)
        end
      end
    end
  end
    
  def first_todo
    background black
    stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "finding first forum with unread messages..."
    end
    forums_todo = (@@bbs.forums('todo').to_a.map{ |k| k[0] } - [1]).sort
    if forums_todo.length > 0
      forum_id = forums_todo[0]
#      visit "/first_unread/#{forum_id}"
      visit "/forum/#{forum_id}"
    else
      visit "/forums"
    end
  end

  def first_unread(forum_id)
    info "first_unread for forum_id #{forum_id}"
    background black

    stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "finding first unread message in forum #{forum_id}..."
    end

    Thread.new {
      @forum =  @@bbs.jump(forum_id)
      noteids = @forum.noteids.map { |n| n.to_i }.sort
      first_unread_msg = @forum.first_unread.to_i
      first_unread_found = noteids.detect { |noteid| noteid >= first_unread_msg }
      if first_unread_found
        visit "/message/#{forum_id}/#{first_unread_found}/forward"
      else
        visit "/first_todo"
      end
   }
  end

  def mark_read(forum_id, msgnum)
    first_unread_msg = @@forum_cache[forum_id][:first_unread]
    if msgnum.to_i >= first_unread_msg
      @@forum_cache[forum_id][:first_unread] = msgnum.to_i + 1
      Thread.new {
        with_new_bbs_connection { | bbs | bbs.jump(forum_id).first_unread = msgnum.to_i + 1 }
      }
    end 

  end

  def mark_unread(forum_id,msgnum)
    @forum =  @@bbs.jump(forum_id)
    first_unread_msg = @forum.first_unread.to_i
    if msgnum.to_i < first_unread_msg
      @forum.first_unread = msgnum
    end
    visit "/forum/#{forum_id}"
  end


  def actions(list)
    linklist = []
    list.each do | item |
      linklist << link(item[1], :click => item[2] )
      linklist << " " unless item == list.last
    end

    keypressproc = Proc.new do | key |
      found = list.assoc(key)
      if found
        action = found[2]
        if action.respond_to? :call
          action.call
        else
          visit action
        end
      end
    end
    return linklist, keypressproc
  end

  def store_message(db, msghash)
    sql = "INSERT INTO messages VALUES( ?, ?, ?, ?, ?, ?)"
    db.execute(sql, msghash[:forum_id], msghash[:message_id], msghash[:date], msghash[:body], msghash[:author], msghash[:authority])
  end

  def get_message_from_db(db, forum_id, msgnum)
    sql = "SELECT * FROM messages WHERE forum_id = ? AND message_id = ?;"
    result = db.get_first_row(sql, forum_id, msgnum) 
    return nil unless result
    msg = {}
    [:forum_id, :message_id, :date, :body, :author, :authorty].each_with_index do | k, i |
      msg[k] = result[i]
    end
    return msg
  end

  def get_message_from_bbs_and_store(forum_id, msgnum, bbs=nil, msg_store=nil)
    bbs ||=@@bbs
    msg_store ||=@@msg_store
    msg = {}
    post = bbs.jump(forum_id).read(msgnum)
    [:date, :author, :body, :authority].each { |k| msg[k] = post.send(k) }
    msg[:message_id] = msgnum
    msg[:forum_id] = forum_id
    store_message(msg_store, msg) if msg_store
    msg
  end

  def get_message_with_caching(forum_id, msgnum, bbs=nil, msg_store=nil)
    bbs ||=@@bbs
    msg_store ||=@@msg_store
    msg = get_message_from_db(@@msg_store, forum_id, msgnum) if @@msg_store
    unless msg
      msg = get_message_from_bbs_and_store(forum_id, msgnum, bbs, msg_store)
    end
    msg
  end

  def message(forum_id,msgnum, direction)
    forum_id=forum_id.to_i
    msgnum=msgnum.to_i
    background black
    stack STACKSTYLE do
      background gold, :curve => 20
      border black, :curve => 20
      @messagestack = stack { para "loading message #{msgnum} in forum #{forum_id}..." }
    end

    Thread.new {
      mark_read(forum_id, msgnum)
      post_ids = @@forum_cache[forum_id][:noteids]
      post_index = post_ids.index(msgnum)
      remaining = post_ids.length - post_index - 1
      msg_next = post_ids[post_index + 1] if post_index < (post_ids.length - 1)
      msg_prev = post_ids[post_index - 1] if post_index > 0
        

      msg = get_message_with_caching(forum_id, msgnum)
      while not msg
        info "waiting for message to show up in the cache..."
        sleep 1
        msg = get_message_from_db(@@msg_store, forum_id, msgnum)
      end
      
      action_list = []
      if msg_prev
        action_list << [ "p", "[p]revious", "/message/#{forum_id}/#{msg_prev}/backward"]
      end
      if msg_next
        action_list << [ "n", "[n]ext","/message/#{forum_id}/#{msg_next}/forward" ]
      end
      action_list << [ "r" , "[r]eply",  "/new_reply/#{forum_id}/#{msgnum}" ]
      action_list << [ "s" , "[s]top reading", "/forum/#{forum_id}" ]
      action_list << [ "u", "mark [u]nread", "/mark_unread/#{forum_id}/#{msgnum}" ]
      action_list << [ "c", "[c]opy to clipboard",  
                       Proc.new { self.clipboard=@whole_message; 
                         alert( "Copied to clipboard.") } ]
      if direction == 'forward' and msg_next
        action_list << [ " ", "[ ]continue", "/message/#{forum_id}/#{msg_next}/forward" ]
      elsif direction == 'backward' and msg_next
        action_list << [ " ", "[ ]continue", "/message/#{forum_id}/#{msg_prev}/backward" ]
      else
        action_list << [ " ", "[ ]continue", "/forum/#{forum_id}" ]
      end
      action_list << [ "q", "[q]uit", Proc.new { exit()} ]
      
      linklist, keypressproc = actions(action_list)
      keypress { | key |  
        keypressproc.call(key) 
      }

      body_urls = msg[:body].scan(URLRE)

      @messagestack.clear do
        para *linklist
        @whole_message = ( "#{msg[:date]} from #{msg[:author]}\n" + 
                           "#{msg[:body]}" + 
                           "[#{@@forum_cache[forum_id][:name]}> msg #{msgnum} (#{ remaining } remaining)]")
        
        stack STACKSTYLE do
          background aliceblue, :curve => 20
          border black, :curve => 20
          para @whole_message
          body_urls.each do | a_url |
            para link(a_url, :click => a_url)
          end
        end
      end
    }
  end

  def new_reply(forum_id, msgnum)
    @post = @@bbs.jump(forum_id).read(msgnum)
    old_body = @post.body.split("\n").map{ |line| "> #{line}" }.join("\n")
    quote = "#{@post.author} wrote:\n#{old_body}\n\n"
    background black
    stack STACKSTYLE do
      background lime, :curve => 20
      border black, :curve => 20
      tagline "New Post"
      para link("back", :click => "/message/#{forum_id}/#{msgnum}/forward")
      @post_box = edit_box quote, :width => 500, :height => 300
      button "post" do
        text = @post_box.text
        new_post = @@bbs.jump(forum_id).post(text)
        visit("/forum/#{forum_id}");
      end
    end
  end
  
  def new_post(forum_id)
    background black
    stack STACKSTYLE do
      background lime, :curve => 20
      border black, :curve => 20
      tagline "New Post"
      para link("back", :click => "/forum/#{forum_id}")
      @post_box = edit_box :width => 500, :height => 300
      button "post" do
        text = @post_box.text
        new_post = @@bbs.jump(forum_id).post(text)
        visit("/forum/#{forum_id}");
      end
    end
  end
end

Shoes.app :width => 800
