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
  url '/login_error/(.+)', :login_error
  url '/bbs', :bbs
  url '/do_login/([^\/]+)/(.+)', :do_login
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

  def page_box
    st = nil
    background black
    stack  :margin => 20 do
      background randcolor(:dark), :curve => 20
      st = stack :margin => 20 do
        yield if block_given?
      end
    end
    st
  end


  def section_box
    st = nil
    stack :margin => 20 do
      background randcolor(:light, 0.5), :curve => 20
      st = stack :margin => 20 do
        info "yielding..."
        yield if block_given?
      end
    end
    st
  end

  def chunk_section_box(text, hidden=true)
    the_flow = nil
    section_box do
      flow(:click => Proc.new { the_flow.toggle },
           :margin => 20
           ) do 
        background rgb(1.0, 1.0, 1.0, 0.5), :curve => 20
        caption text, :align => 'right', :stroke => randcolor(:realdark), :margin => 20
      end
      the_flow = flow :hidden => hidden do
        yield
      end
    end
  end

  def header_box(linklist=[], text = "")
    section_box do
      flow do
        flow( :width => -200) do
          para *linklist 
        end
        flow( :width => 200) do
          tagline( text, :stroke => randcolor(:realdark), 
                   :margin => 20, :align => 'right')
        end
      end
    end
  end

  def chunk_box
    stack :width => 200 do
      background rgb(1.0, 1.0, 1.0, 0.5), :curve => 10, :margin => 20
      stack :margin => 20 do
        yield if block_given?
      end
    end
  end

  def randcolor(bias=nil, alpha = 1.0)
    target, range = case bias
                    when :dark: [ 0.3, 0.3 ]
                    when :light: [0.8, 0.4]
                    when :realdark: [ 0.1, 0.2]
                    else [0.5, 0.6]
                    end
    rgb( ( (rand - 0.5) * range ) + target,
         ( (rand - 0.5) * range ) + target,
         ( (rand - 0.5) * range ) + target,
         alpha)
  end


  def license
    info "license"
    page_box do
      section_box do
        background aliceblue, :curve => 20
        para link('back', :click => '/login')
        para LICENSE
      end
    end
  end

  def recording_last_read(forum_id)
    if should_record_last_read(forum_id)
      clear do
        page_box do
          para "recording last read message..."
        end
      end
      Thread.new do
        record_last_read(forum_id)
        yield
      end
    else
      yield
    end
  end

  def should_record_last_read(forum_id)
    forum_id = forum_id.to_i
    info "should_record_last_read for #{forum_id}"
    cached = @@forum_cache[forum_id]
    cached[:first_unread] != cached[:server_first_unread]
  end

  def record_last_read(forum_id)
    forum_id = forum_id.to_i
    info "record_last_read for #{forum_id}"
    cached = @@forum_cache[forum_id]
    forum = @@bbs.jump(forum_id)
    forum.first_unread = cached[:first_unread]
    cached[:server_first_unread] = cached[:first_unread]
    
    if cached[:first_unread] > cached[:noteids].last
      @@bbs_cache[:todo].delete(forum_id)
    end
    
    if cached[:first_unread] <= cached[:noteids].last
      @@bbs_cache[:todo][forum_id] = @@bbs_cache[:all][forum_id]
    end
  end

  def quit_from_forum(id)
    info "quit_from_forum"
    page_box do
      "Quitting..."
    end
    recording_last_read(id) do
      exit()
    end
  end

  def quit
    info "quit"
    exit()
  end

  def login_error(error)
    stack do
      para err.message
      link("try again",:click => '/')
    end
  end

  def do_login(username, password)
    page_box do
      para "logging in..."
    end
    Thread.new do
      begin
        @@bbs = Raccdoc::Connection.new(:user => username, :password => password,
                                        :host => HOST,
                                        :port => PORT
                                        )
        YAML::Store.new('bbsconfig.yaml').transaction do |store|
          store['username'], store['password'] = username, password
        end
        visit '/load_bbs'
      rescue RuntimeError => err
        debug "error: #{err.message}"
        @@bbs = nil
        visit "/login_error/#{err.message}"
      end
    end
  end

  def login
    username, password = nil, nil
    YAML::Store.new('bbsconfig.yaml').transaction(true) do |store|
      username, password = store['username'], store['password']
    end
    
    keypress do | key |
      if key == "\n"
        visit "/do_login/#{@username_line.text}/#{@password_line.text}"
      end
    end
    @content = page_box do
      section_box do
        tagline "Login", :stroke => randcolor(:realdark), :align => right
        para "username:"
        @username_line = app.edit_line "#{ username }"
        para "password:"
        @password_line = app.edit_line "#{ password }", :secret => true
        button "login" do
          visit "/do_login/#{@username_line.text}/#{@password_line.text}"
        end
        para(link( 'license', :click => '/license' ))
      end
    end
  end

  def quit
    page_box do
      exit()
    end
  end

  def leave_forum(id)
    info "leave forum #{id}"
    page_box
    page_box do
      para "leaving forum #{id}..."
    end
    recording_last_read(id) do
      visit '/bbs'
    end
  end
  

  def load_bbs
    info "load_bbs"
    page_box do
      para "loading forums..."
    end
    Thread.new do
      @@bbs_cache[:all] = @@bbs.forums('all')
      @@bbs_cache[:todo] = @@bbs.forums('todo')
      @@bbs_cache[:joined] = @@bbs.forums('joined')
      visit '/bbs'
    end
  end

  def bbs
    info "bbs"
    forums = @@bbs_cache[:all]
    forums_todo = (@@bbs_cache[:todo].keys - [1]).sort
    forums_joined = (@@bbs_cache[:joined].keys - forums_todo - [1]).sort
    forums_all = (@@bbs_cache[:all].keys - forums_joined - forums_todo - [1]).sort
    # delete mail
    forums.delete(1)
    action_list = []
    if forums_todo.length > 0
      action_list << [ ' ', '[ ]first forum with unread', "/enter_forum/#{forums_todo.first}"]
    else
      action_list << [ ' ', '[ ]refresh_forums', "/load_bbs"]
    end
    action_list << [ 'q', '[q]uit', '/quit' ]

    linklist, keypressproc = actions( action_list )
    keypress { | key | keypressproc.call(key) }
    open_shown = false
    page_box do
      header_box( linklist, "Forums")
      [ ["Unread", forums_todo ],
        ["Subscribed", forums_joined ],
        ["Zapped", forums_all ]].each do | group |
        group_name, ordered_ids = *group
        if ordered_ids.length > 0
          chunk_section_box(group_name, open_shown) do
            ordered_ids.each do | id |
              data = forums[id]
              chunk_box do
                para link("#{id}> #{data[:name]}", :click => "/enter_forum/#{id}")
              end
            end
          end
          open_shown = true
        end
      end
    end
  end

  def goto_next_from(forum_id)
    forum_id = forum_id.to_i
    # id is forum to jump *from*
    page_box do
      para "leaving forum #{forum_id}.."
    end
    cache = @@forum_cache[forum_id]
    cache[:first_unread] = cache[:noteids].last + 1
      
    todo_list = @@bbs_cache[:todo].keys.sort
    recording_last_read(forum_id) do
      if todo_list.length > 0
        visit "/enter_forum/#{@@bbs_cache[:todo].keys.first}"
      else
        visit "/bbs"
      end
    end
  end
  
  def switch_forum(old_id, new_id)
    old_id, new_id = old_id.to_i, new_id.to_i
    recording_last_read(old_id) do
      visit "/enter_forum/#{new_id}"
    end
  end

  def enter_forum(id)
    page_box do
      para "loading forum #{id}..."
    end
    info "enter_forum #{id}"
    id = id.to_i
    Thread.new do
      # we pull stuff into forum_cache only when we enter a new forum.
      forum = @@bbs.jump(id)
      cache  = {}
      first_unread = forum.first_unread.to_i
      info "first_unread: #{ first_unread.inspect }"
      cache[:server_first_unread] = first_unread
      cache[:first_unread] = first_unread
      info "first unread: #{first_unread.inspect}"
      info "forum_id info: #{ @@bbs_cache[:all][id].inspect }"
      noterange = "#{ first_unread - HORIZON }-#{ first_unread + HORIZON }"
      cache[:noteids] = forum.noteids(noterange).sort
      if cache[:noteids].length == 0 # uh oh
        noterange = "#{ @@bbs_cache[:all][id][:lastnote].to_i - HORIZON }-#{ @@bbs_cache[:all][id][:lastnote] }"
        cache[:noteids] = forum.noteids(noterange).sort
      end
      info "noterange: #{noterange}"
      cache[:post_headers] = forum.post_headers(noterange)
      cache[:name] = forum.name
      cache[:post_ok] = forum.post?
      cache[:admin] = forum.admin
      cache[:anonymous] = forum.anonymous
      cache[:private] = forum.private
      @@forum_cache[id] = cache
      visit "/forum/#{id}"
    end
  end

  def forum(id)
    info "forum #{id}"
    id = id.to_i
    cache = @@forum_cache[id]
    unless cache
      visit "/enter_forum/#{id}"
    end
    
    first_unread = cache[:first_unread]
    posts = cache[:post_headers]
    noteids = cache[:noteids]
    msgs_unread = noteids.select { |msg| msg.to_i >= first_unread }
    msgs_read = noteids.select { |msg| msg.to_i < first_unread }
    actionlist =  [[ 'e', '[e]nter msg', "/new_post/#{id}"],
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
                  ]
    
    linklist, keypressproc = actions(actionlist)
    
    keypress { | key |  keypressproc.call(key) }
    open_shown = false
    page_box do
      header_box(linklist, cache[:name])
      [ [ "Unread", msgs_unread,  ],
        [ "Read", msgs_read,  ]].each do | pair |
        group_name, ordered_ids = *pair
        if ordered_ids.length > 0
          chunk_section_box(group_name, open_shown) do
            ordered_ids.reverse.each do | post_id |
              post = posts[post_id.to_s]
              chunk_box do
                para link("#{ post_id }/#{post[:author]}/#{post[:date]}/#{post[:size]}", :click => "/message/#{id}/#{post_id}/forward")
                para post[:subject]
              end
            end
          end
          open_shown = true
        end
      end
    end
  end

  def foruminfo(id)
    id = id.to_i
    info "foruminfo #{id}"
    @page = page_box do
      para "loading info for forum #{id}..."
    end

    linklist, keypressproc = actions [[ 'b', '[b]ack', "/forum/#{id}"],
                                      [ 'p', '[e]nter msg', "/new_post/#{id}"],
                                      [ " ", "[ ]first unread message", "/first_unread/#{id}" ],
                                      [ "q", "[q]uit", "/quit_from_forum/#{id}" ]
                                     ]
    keypress { | key |  keypressproc.call(key) }

    Thread.new do
      @@forum_cache[:forum_info] ||= @@bbs.jump(id).forum_information
      info = @@forum_cache[:forum_info]
      the_body = info[:body]
      body_urls = the_body.scan(URLRE)
      @page.clear do
        section_box do
          para *linklist
        end
        section_box do
          caption "Forum moderator is #{@@forum_cache[id][:admin]}."
          caption "Forum info last updated #{info[:date]} by #{info[:from]}"
          para "#{info[:body]}"
          body_urls.each do | a_url |
            para link(a_url, :click => a_url)
          end
        end
      end
    end
  end

  def first_unread(forum_id)
    info "first_unread for forum_id #{forum_id}"
    forum_id = forum_id.to_i
    cache = @@forum_cache[forum_id]

    page_box do
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

    @page = page_box do
      para "loading messge #{msgnum} in forum #{forum_id}"
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

    Thread.new do
      msg = get_message(forum_id, msgnum)
      body_urls = msg[:body].scan(URLRE)
      authority = " (#{msg[:authority]})" if msg[:authority]
      @whole_message = ( "#{msg[:date]} from #{msg[:author]}#{authority}\n" + 
                         "#{msg[:body]}" + 
                         "[#{@@forum_cache[forum_id][:name]}> msg #{msgnum} (#{ remaining } remaining)]")
      
      @page.clear do
        section_box do
          para *linklist
        end
        section_box do
        para @whole_message
          body_urls.each do | a_url |
            para link(a_url, :click => a_url)
          end
        end
      end
    end
    if @@forum_cache[forum_id][:first_unread] <= msgnum
      @@forum_cache[forum_id][:first_unread] = msgnum + 1
    end

  end
    
  def new_reply(forum_id, msgnum)
    @page = page_box do
      "loading message #{msgnum} in forum #{forum_id} to reply to..."
    end

    Thread.new do
      msg = get_message(forum_id, msgnum)
      old_body = msg[:body].split("\n").map{ |line| "> #{line}" }.join("\n")
      quote = "#{msg[:author]} wrote:\n#{old_body}\n\n"
      @page.clear do
        section_box do
          para link("back", :click => "/message/#{forum_id}/#{msgnum}/forward")
          tagline "Post to forum #{forum_id}", :stroke => randcolor(:realdark), :align => 'right'
          @post_box = edit_box quote, :width => 500, :height => 300, :margin => 20
          button "post" do
            text = @post_box.text
            new_post = @@bbs.jump(forum_id).post(text)
            recording_last_read(forum_id) do
              visit("/enter_forum/#{forum_id}") # refresh cache cause there's a new post!
            end
          end
        end
      end
    end
  end
  
  def new_post(forum_id)
    @page = page_box do
      section_box do
        tagline "New Post", :stroke => randcolor(:realdark), :align => right
        para link("back", :click => "/forum/#{forum_id}")
        @post_box = edit_box :width => 500, :height => 300, :margin => 20
        button "post" do
          text = @post_box.text
          @page.clear do
            para "posting message..."
          end
          Thread.new do
            new_post = @@bbs.jump(forum_id).post(text)
            recording_last_read(forum_id) do
              visit("/enter_forum/#{forum_id}") # refresh cache cause there's a new post!
            end
          end
        end
      end
    end
  end
end


Shoes.app :width => 850
