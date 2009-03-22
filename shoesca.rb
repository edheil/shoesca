Shoes.setup do
  Gem.sources = ['http://gems.github.com/', 'http://gems.rubyforge.org/']
  gem 'minter-raccdoc'
end

require 'raccdoc'
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
  URLRE = Regexp.new('https?://[^ \n\)]+')
  HORIZON = 200 # the range of noteids retrieved before or after the first_unread
 
  url '/', :login
  url '/bbs', :bbs
  url '/load_bbs', :load_bbs
  url '/quit_from_forum/(\d+)', :quit_from_forum
  url '/quit', :quit
  url '/goto_next_from/(\d+)', :goto_next_from
  url '/login', :login
  url '/license', :license
  url '/enter_forum/(\d+)', :enter_forum
  url '/forum/(\d+)', :forum
  url '/leave_forum/(\d+)', :leave_forum
  url '/switch_forum/(\d+)/(\d+)', :switch_forum
  url '/foruminfo/(\d+)', :foruminfo
  url '/first_unread/(\d+)', :first_unread
  url '/message/(\d+)/(\d+)/(.*)', :message
  url '/mark_unread/(\d+)/(\d+)', :mark_unread
  url '/new_post/(\d+)', :new_post
  url '/new_reply/(\d+)/(\d+)', :new_reply
  @@bbs = nil
  @@forum_cache = {}
  @@bbs_cache = {}

  def license
    info "license"
    background black
    stack :margin => 20 do
      background aliceblue, :curve => 20
      border black, :curve => 20
      para link('back', :click => '/login')
      para LICENSE
    end
  end


  def record_last_read(forum_id)
    forum_id = forum_id.to_i
    info "record_last_read for #{forum_id}"
    cached = @@forum_cache[forum_id]
    if cached
      info "got cache"
      info "seeing if #{ cached[:first_unread] } != #{ cached[:server_first_unread] }"
      if cached[:first_unread] != cached[:server_first_unread]
        info "yep.  must modify server's first_unread"
        forum = @@bbs.jump(forum_id)
        info "setting first_unread to #{cached[:first_unread]}"
        forum.first_unread = cached[:first_unread]
        cached[:server_first_unread] = cached[:first_unread]

        info "after the change..."
        if cached[:first_unread] > cached[:noteids].last
          info "first_unread is greater than last_note.  deleting #{forum_id} from todo"
          @@bbs_cache[:todo].delete(forum_id)
        end

        if cached[:first_unread] <= cached[:noteids].last
          info "first_unread is less than or equal to last_note.  adding #{forum_id} to todo"
          @@bbs_cache[:todo][forum_id] = @@bbs_cache[:all][forum_id]
        end
      end
    end
  end

  def quit_from_forum(id)
    info "quit_from_forum"
    record_last_read(id)
    exit()
  end

  def quit
    info "quit"
    exit()
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
          visit '/load_bbs'
        end
     end
    end


    @mainstack = stack :margin => 20 do
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

  def quit
    exit()
  end

  def leave_forum(id)
    info "leave forum #{id}"
    record_last_read(id)
    visit '/bbs'
  end

  def load_bbs
    background black
    @@bbs_cache[:all] = @@bbs.forums('all')
    @@bbs_cache[:todo] = @@bbs.forums('todo')
    @@bbs_cache[:joined] = @@bbs.forums('joined')
    visit '/bbs'
  end

  def bbs
    background black

    @mainstack = stack :margin => 20 do
      background aliceblue, :curve => 20
      border black, :curve => 20
      para "loading bbs..."
    end
    
    forums = @@bbs_cache[:all]
    forums_todo = (@@bbs_cache[:todo].keys - [1]).sort
    forums_joined = (@@bbs_cache[:joined].keys - forums_todo - [1]).sort
    forums_all = (@@bbs_cache[:all].keys - forums_joined - forums_todo - [1]).sort
    # delete mail
    forums.delete(1)
    action_list = []
    if forums_todo.length > 0
      action_list << [ ' ', '[ ]first forum with unread', "/forum/#{forums_todo.first}"]
    else
      action_list << [ ' ', '[ ]refresh_forums', "/load_bbs"]
    end
    action_list << [ 'q', '[q]uit', '/quit' ]

    linklist, keypressproc = actions( action_list )
    keypress { | key | keypressproc.call(key) }
    @mainstack.clear do
      background aliceblue, :curve => 20
      border black, :curve => 20
      para *linklist
      #  100 =>  { :topic => "100", :flags => 'nosubject,sparse,cananonymous', 
      #            :name => "Some Forum", :lastnote => "99999", :admin => "Some Dude" }
      [ ["Unread", forums_todo, ivory],
        ["Subscribed", forums_joined, lightgrey],
        ["Zapped", forums_all, darkslateblue]].each do | group |
        group_name, ordered_ids, coloring = *group
        stack :margin => 20 do
          background white, :curve => 20
          border black, :curve => 20
          caption group_name
          flow do
            ordered_ids.each do | id |
              data = forums[id]
              stack :width => 200, :margin => 20 do
                background coloring, :curve => 10
                border black, :curve => 10
                para link("#{id}> #{data[:name]}", :click => "/enter_forum/#{id}")
              end
            end
          end
        end
      end
    end
  end

  def goto_next_from(forum_id)
    forum_id = forum_id.to_i
    # id is forum to jump *from*
    cache = @@forum_cache[forum_id]
    cache[:first_unread] = cache[:noteids].last + 1
    record_last_read(forum_id)
    todo_list = @@bbs_cache[:todo].keys.sort
    if todo_list.length > 0
      visit "/enter_forum/#{@@bbs_cache[:todo].keys.first}"
    else
      visit "/bbs"
    end
  end
  
  def switch_forum(old_id, new_id)
    old_id, new_id = old_id.to_i, new_id.to_i
    record_last_read(old_id)
    visit "/enter_forum/#{new_id}"
  end

  def enter_forum(id)
    info "enter_forum #{id}"
    id = id.to_i
    background black
    # we pull stuff into forum_cache only when we enter a new forum.
    forum = @@bbs.jump(id)
    cache  = {}
    first_unread = forum.first_unread.to_i
    cache[:server_first_unread] = first_unread
    cache[:first_unread] = first_unread
    noterange = "#{ first_unread - HORIZON }-#{ first_unread + HORIZON }"
    cache[:noteids] = forum.noteids(noterange).sort
    cache[:post_headers] = forum.post_headers(noterange)
    cache[:name] = forum.name
    cache[:post_ok] = forum.post?
    cache[:admin] = forum.admin
    cache[:anonymous] = forum.anonymous
    cache[:private] = forum.private
    @@forum_cache[id] = cache
    visit "/forum/#{id}"
  end

  def forum(id)
    info "forum #{id}"
    id = id.to_i
    background black
    cache = @@forum_cache[id]
    unless cache
      visit "/enter_forum/#{id}"
    end
    
    first_unread = cache[:first_unread]
    posts = cache[:post_headers]
    noteids = cache[:noteids]
    msgs_unread = noteids.select { |msg| msg.to_i >= first_unread }
    msgs_read = noteids.select { |msg| msg.to_i < first_unread }
    
    linklist, keypressproc = actions( [[ 'e', '[e]nter msg', "/new_post/#{id}"],
                                       [ 'i', '[i]nfo', "/foruminfo/#{id}"],
                                       [ 'l', 'forum [l]ist', "/leave_forum/#{id}"],
                                       [ 'f', 'read [f]orward',
                                         "/message/#{id}/#{noteids.first}/forward"],
                                       [ 'b', 'read [b]ackward', 
                                         "/message/#{id}/#{noteids.last}/backward"],
                                       [ 'g', '[g]oto next forum with unread messages', 
                                         "/goto_next_from/#{id}"],
                                       [ ' ', '[ ]first unread', "/first_unread/#{id}"],
                                       [ 'q', '[q]uit', "/quit_from_forum/#{id}" ]
                                      ] )
    
    keypress { | key |  keypressproc.call(key) }
    @mainstack = stack :margin => 20 do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "loading forum #{id}..."
    end

    @mainstack.clear do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      tagline cache[:name]
      para *linklist
      [ [ "Unread", msgs_unread,  ],
        [ "Read", msgs_read,  ]].each do | pair |
        group_name, ordered_ids = *pair
        stack :margin => 20 do
          background white, :curve => 20
          border black, :curve => 20
          caption group_name
          flow do
            ordered_ids.reverse.each do | post_id |
              post = posts[post_id.to_s]
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
  end

  def foruminfo(id)
    info "foruminfo #{id}"
    background black
    
    linklist, keypressproc = actions [[ 'b', '[b]ack', "/forum/#{id}"],
                                      [ 'p', '[e]nter msg', "/new_post/#{id}"],
                                      [ " ", "[ ]first unread message", "/first_unread/#{id}" ],
                                      [ "q", "[q]uit", "/quit_from_forum/#{id}" ]
                                     ]
    keypress { | key |  keypressproc.call(key) }
    
    stack :margin => 20 do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para *linklist
      @@forum_cache[:forum_info] ||= @@bbs.jump(id).forum_information
      info = @@forum_cache[:forum_info]
      the_body = info[:body]
      body_urls = the_body.scan(URLRE)
      stack :margin => 20 do
        background lightgrey, :curve => 10
        border black, :curve => 10
        caption "Forum moderator is #{@@forum_cache[:admin]}."
        caption "Forum info last updated #{info[:date]} by #{info[:from]}"
        para "#{info[:body]}"
        body_urls.each do | a_url |
          para link(a_url, :click => a_url)
        end
      end
    end
  end

  def first_unread(forum_id)
    info "first_unread for forum_id #{forum_id}"
    forum_id = forum_id.to_i
    background black
    cache = @@forum_cache[forum_id]

    stack :margin => 20 do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "finding first unread message in forum #{forum_id}..."
    end

    noteids = cache[:noteids]
    first_unread_msg = cache[:first_unread]
    first_unread_found = noteids.detect { |noteid| noteid >= first_unread_msg }
    if first_unread_found
      visit "/message/#{forum_id}/#{first_unread_found}/forward"
    else
      visit "/leave_forum/#{forum_id}"
    end
  end

  def mark_unread(forum_id,msgnum)
    forum_id = forum_id.to_i; msgnum = msgnum.to_i
    cache = @@forum_cache[forum_id]
    if msgnum < cache[:first_unread]
      cache[:first_unread] = msgnum
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
          info "visiting <#{action}>"
          visit action
        end
      end
    end
    return linklist, keypressproc
  end

  def get_message(forum_id, msgnum)
    msg = {}
    post = @@bbs.jump(forum_id).read(msgnum)
    [:date, :author, :body, :authority].each { |k| msg[k] = post.send(k) }
    msg[:message_id] = msgnum
    msg[:forum_id] = forum_id
    msg
  end

  def message(forum_id,msgnum, direction)
    forum_id=forum_id.to_i
    msgnum=msgnum.to_i
    background black
    stack :margin => 20 do
      background gold, :curve => 20
      border black, :curve => 20
      @messagestack = stack { para "loading message #{msgnum} in forum #{forum_id}..." }
    end

    post_ids = @@forum_cache[forum_id][:noteids]
    post_index = post_ids.index(msgnum)
    remaining = post_ids.length - post_index - 1
    msg_next = post_ids[post_index + 1] if post_index < (post_ids.length - 1)
    msg_prev = post_ids[post_index - 1] if post_index > 0
    
    action_list = []
    if msg_prev
      action_list << [ "p", "[p]revious", "/message/#{forum_id}/#{msg_prev}/backward"]
    end
    if msg_next
      action_list << [ "n", "[n]ext","/message/#{forum_id}/#{msg_next}/forward" ]
    end
    action_list << [ "r" , "[r]eply",  "/new_reply/#{forum_id}/#{msgnum}" ]
    action_list << [ "e" , "[e]nter message",  "/new_post/#{forum_id}" ]
    action_list << [ "s" , "[s]top reading", "/forum/#{forum_id}" ]
    action_list << [ "u", "mark [u]nread", "/mark_unread/#{forum_id}/#{msgnum}" ]
    action_list << [ "c", "[c]opy to clipboard",  
                     Proc.new { self.clipboard=@whole_message; 
                       alert( "Copied to clipboard.") } ]
    if direction == 'forward'
      if msg_next
        action_list << [ " ", "[ ]continue", "/message/#{forum_id}/#{msg_next}/forward" ]
      else
        action_list << [ " ", "[ ]continue", "/forum/#{forum_id}" ]
      end
      if msg_prev 
        action_list << [ "b", "[b]ack up", "/message/#{forum_id}/#{msg_prev}/backward" ]
      else
        action_list << [ " ", "[b]ack up", "/forum/#{forum_id}" ]
      end
    elsif direction == 'backward'
      if msg_prev
        action_list << [ " ", "[ ]continue", "/message/#{forum_id}/#{msg_prev}/backward" ]
      else
        action_list << [ " ", "[ ]continue", "/forum/#{forum_id}" ]
      end
      if msg_next
        action_list << [ "b", "[b]ack up", "/message/#{forum_id}/#{msg_next}/forward" ]
      else
        action_list << [ " ", "[b]ack up", "/forum/#{forum_id}" ]
      end
    end
    action_list << [ "q", "[q]uit", "/quit_from_forum/#{forum_id}" ]
      
    linklist, keypressproc = actions(action_list)
    keypress { | key |  
      keypressproc.call(key) 
    }

    msg = get_message(forum_id, msgnum)
    body_urls = msg[:body].scan(URLRE)
    authority = " (#{msg[:authority]})" if msg[:authority]
    @whole_message = ( "#{msg[:date]} from #{msg[:author]}#{authority}\n" + 
                       "#{msg[:body]}" + 
                       "[#{@@forum_cache[forum_id][:name]}> msg #{msgnum} (#{ remaining } remaining)]")

    @messagestack.clear do
      para *linklist
      stack :margin => 20 do
        background aliceblue, :curve => 20
        border black, :curve => 20
        para @whole_message
        body_urls.each do | a_url |
          para link(a_url, :click => a_url)
        end
      end
    end
    if @@forum_cache[forum_id][:first_unread] <= msgnum
      @@forum_cache[forum_id][:first_unread] = msgnum + 1
    end
  end
    
  def new_reply(forum_id, msgnum)
    @post = @@bbs.jump(forum_id).read(msgnum)
    old_body = @post.body.split("\n").map{ |line| "> #{line}" }.join("\n")
    quote = "#{@post.author} wrote:\n#{old_body}\n\n"
    background black
    stack :margin => 20 do
      background lime, :curve => 20
      border black, :curve => 20
      tagline "New Post"
      para link("back", :click => "/message/#{forum_id}/#{msgnum}/forward")
      @post_box = edit_box quote, :width => 500, :height => 300, :margin => 20
      button "post" do
        text = @post_box.text
        new_post = @@bbs.jump(forum_id).post(text)
        visit("/enter_forum/#{forum_id}") # refresh cache cause there's a new post!
      end
    end
  end
  
  def new_post(forum_id)
    background black
    stack :margin => 20 do
      background lime, :curve => 20
      border black, :curve => 20
      tagline "New Post"
      para link("back", :click => "/forum/#{forum_id}")
      @post_box = edit_box :width => 500, :height => 300, :margin => 20
      button "post" do
        text = @post_box.text
        new_post = @@bbs.jump(forum_id).post(text)
        visit("/enter_forum/#{forum_id}") # refresh cache cause there's a new post!
      end
    end
  end
end

Shoes.app :width => 800
