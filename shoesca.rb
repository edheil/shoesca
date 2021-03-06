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
  url '/do_login/([^\/]+)/(.+)', :do_login
  url '/load_bbs', :load_bbs
  url '/quit_from_forum/(\d+)', :quit_from_forum
  url '/quit', :quit
  url '/goto_next_from/(\d+)', :goto_next_from
  url '/login', :login
  url '/error', :error
  url '/license', :license
  url '/config', :config
  url '/enter_forum/(\d+)', :enter_forum
  url '/forum/(\d+)', :forum
  url '/leave_forum/(\d+)', :leave_forum
  url '/switch_forum/(\d+)/(\d+)', :switch_forum
  url '/foruminfo/(\d+)', :foruminfo
  url '/message/(\d+)/(\d+)/(.*)', :message
  url '/mark_unread/(\d+)/(\d+)', :mark_unread
  url '/new_post/(\d+)', :new_post
  url '/new_reply/(\d+)/(\d+)', :new_reply
  @@bbs = nil
  @@gradients = false
  @@error = nil
  @@forum_cache = {}
  @@bbs_cache = {}
  @@use_threads = true
  @@config = {}

  # PAGES

  def login

    @@bbs = nil
    username, password = nil, nil
    YAML::Store.new('bbsconfig.yaml').transaction(true) do |store|
      username, password = store['username'], store['password']
      @@config = store['config'] || {}
    end

    if @@config['auto_login'] and username and password
      visit "/do_login/#{username}/#{password}"
    end

    setup_keypress

    add_actions( ["\n", '[enter] login', Proc.new {
                     visit "/do_login/#{@username_line.text}/#{@password_line.text}"}
                  ],
                 ['l', '[l]icense', '/license'],
                 ['c', '[c]onfig', '/config'],
                 ['q', '[q]uit', '/quit'] )
    
    @content = page_box do
      header_box( "Login")
      section_box do
        flow { para "username:"; @username_line = app.edit_line "#{ username }" }
        flow { para "password:"; @password_line = app.edit_line "#{ password }", 
          :secret => true }
        button "login" do
          visit "/do_login/#{@username_line.text}/#{@password_line.text}"
        end
      end
    end
  end

  def do_login(username, password)
    setup_keypress
    @page = page_box do
      para "logging in..."
    end
    threadingly do
      rescuingly do
        info "making connection"
        @@bbs = Raccdoc::Connection.new(:user => username, :password => password,
                                        :host => HOST,
                                        :port => PORT
                                        )
        YAML::Store.new('bbsconfig.yaml').transaction do | store |
          if @@config['save_username']
            store['username']=username
          else
            store.delete('username')
          end
          if @@config['save_password']
            store['password'] = password
          else
            store.delete('password')
          end
        end
        visit '/load_bbs'
      end
    end
  end

  def config
    setup_keypress
    if @@bbs
      add_actions ['b', '[b]ack to bbs', '/bbs']
    else
      add_actions ['b', '[b]ack to login', '/']
    end
    add_actions  ['q', '[q]uit', '/quit']
    @c = {}
    page_box do
      header_box( "Configuration" )
      section_box do
        button "Save configuration", :align => 'right' do
          YAML::Store.new('bbsconfig.yaml').transaction do |store|
            store['config'] ||= {}
            @c.each do | key, control |
              store['config'][key] = @@config[key] = @c[key].checked
            end
          end
          alert "configuration saved."
        end
      end
      chunk_section_box("Login Configuration", true) do
        @c['save_username'] =
          option_box("save username") do | me | 
          @auto_login.checked = false unless me.checked?
        end
        @c['save_password'] =
          option_box("save password") do | me | 
          @auto_login.checked = false unless me.checked?
        end
        @c['auto_login'] = 
          option_box("log in automatically") do | me |
          if me.checked?
            @c['save_username'].checked = true
            @c['save_password'].checked = true
          end
        end
      end
      chunk_section_box("Cosmetic Configuration", true) do
        @c['gradients'] = option_box("gradients")
        @c['white_bkg'] = option_box("white background")
      end
    end
    YAML::Store.new('bbsconfig.yaml').transaction do |store|
      @c.each do | key, control |
        store['config'] ||= {}
        @c[key].checked = store['config'][key]
      end
    end
  end


  def error
    setup_keypress
    add_actions( ['q', '[q]uit', '/quit'],
                 ['b', '[b]ack to login', '/']
                 )
    page_box do
      header_box "Error"
      section_box do
        para @@error
      end
    end
  end

  def license
    setup_keypress
    info "license"
    add_actions( ['b', '[b]ack', '/' ], ['q', '[q]uit', '/quit'])
    page_box do
      header_box("License")
      section_box do
        para LICENSE
      end
    end
  end
  
  def load_bbs
    info "load_bbs"
    page_box do
      para "loading forums..."
    end
    threadingly do
      rescuingly do
        @@bbs_cache[:all] = @@bbs.forums('all')
        @@bbs_cache[:todo] = @@bbs.forums('todo')
        @@bbs_cache[:joined] = @@bbs.forums('joined')
        visit '/bbs'
      end
    end
  end

  def bbs
    setup_keypress
    info "bbs"
    forums = @@bbs_cache[:all]
    forums_todo = (@@bbs_cache[:todo].keys - [1]).sort
    forums_joined = (@@bbs_cache[:joined].keys - forums_todo - [1]).sort
    forums_all = (@@bbs_cache[:all].keys - forums_joined - forums_todo - [1]).sort
    # delete mail
    forums.delete(1)
    if forums_todo.length > 0
      add_actions [ ' ', '[ ]first forum with unread', "/enter_forum/#{forums_todo.first}"]
    else
      add_actions [ ' ', '[ ]refresh_forums', "/load_bbs"]
    end
    add_actions (['c', '[c]onfig', '/config'],
                 [ 'q', '[q]uit', '/quit' ])

    page_box do
      header_box( "Forums")
      [ ["Unread", forums_todo, false ],
        ["Subscribed", forums_joined, true ],
        ["Zapped", forums_all, true ]].each do | group |
        group_name, ordered_ids, hidden = *group
        if ordered_ids.length > 0
          chunk_section_box(group_name, hidden) do
            ordered_ids.each do | id |
              data = forums[id]
              chunk_box do
                para link("#{id}> #{data[:name]}", :click => "/enter_forum/#{id}")
              end
            end
          end
        end
      end
    end
  end

  def enter_forum(id)
    page_box do
      para "loading forum #{id}..."
    end
    info "enter_forum #{id}"
    id = id.to_i
    threadingly do
      rescuingly do
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
  end

  def forum(id)
    setup_keypress
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
    add_actions( [ 'e', '[e]nter msg', "/new_post/#{id}"],
                 [ 'i', '[i]nfo', "/foruminfo/#{id}"],
                 [ 'l', 'forum [l]ist', "/leave_forum/#{id}"],
                 [ 'f', 'read [f]orward',
                   "/message/#{id}/#{noteids.first}/forward"],
                 [ 'b', 'read [b]ackward', 
                   "/message/#{id}/#{noteids.last}/backward"],
                 [ 'g', '[g]oto next forum with unread messages', 
                   "/goto_next_from/#{id}"])
    if msgs_unread.length > 0
      add_actions [ ' ', '[ ]first unread', "/message/#{id}/#{msgs_unread[0]}/forward"]
    else
      add_actions [ ' ', '[ ]forum list', "/leave_forum/#{id}"]
    end
    add_actions [ 'q', '[q]uit', "/quit_from_forum/#{id}" ]
    
    page_box do
      header_box(cache[:name])
      [ [ "Unread", msgs_unread, false  ],
        [ "Read", msgs_read, true  ]].each do | group |
        group_name, ordered_ids, hidden = *group
        if ordered_ids.length > 0
          chunk_section_box(group_name, hidden) do
            ordered_ids.reverse.each do | post_id |
              post = posts[post_id.to_s]
              if post # bizarrely, sometimes we have a noteid with no post headers
                chunk_box do
                  para link("#{ post_id }\n#{post[:author]}\n#{post[:date]}", :click => "/message/#{id}/#{post_id}/forward")
                  para post[:subject]
                end
              end
            end
          end
        end
      end
    end
  end

  def foruminfo(id)
    setup_keypress
    id = id.to_i
    info "foruminfo #{id}"
    @page = page_box do
      para "loading info for forum #{id}..."
    end

    add_actions( [ 'b', '[b]ack', "/forum/#{id}"],
                 [ 'p', '[e]nter msg', "/new_post/#{id}"],
                 [ "q", "[q]uit", "/quit_from_forum/#{id}" ] )

    threadingly do
      rescuingly do
        @@forum_cache[:forum_info] ||= @@bbs.jump(id).forum_information
        info = @@forum_cache[:forum_info]
        the_body = info[:body]
        body_urls = the_body.scan(URLRE)
        @page.clear do
          header_box
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
  end

  def message(forum_id,msgnum, direction)
    setup_keypress
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
      add_actions [ "p", "[p]revious", "/message/#{forum_id}/#{msg_prev}/backward"]
    end
    if msg_next
      add_actions [ "n", "[n]ext","/message/#{forum_id}/#{msg_next}/forward" ]
    end
    add_actions [ "r" , "[r]eply",  "/new_reply/#{forum_id}/#{msgnum}" ]
    add_actions [ "e" , "[e]nter message",  "/new_post/#{forum_id}" ]
    add_actions [ "s" , "[s]top reading", "/forum/#{forum_id}" ]
    add_actions [ "u", "mark [u]nread", "/mark_unread/#{forum_id}/#{msgnum}" ]
    add_actions [ "c", "[c]opy to clipboard",  
                     Proc.new { self.clipboard=@whole_message; 
                       alert( "Copied to clipboard.") } ]
    if direction == 'forward'
      if msg_next
        add_actions [ " ", "[ ]continue", "/message/#{forum_id}/#{msg_next}/forward" ]
      else
        add_actions [ " ", "[ ]continue", "/forum/#{forum_id}" ]
      end
      if msg_prev 
        add_actions [ "b", "[b]ack up", "/message/#{forum_id}/#{msg_prev}/backward" ]
      else
        add_actions [ " ", "[b]ack up", "/forum/#{forum_id}" ]
      end
    elsif direction == 'backward'
      if msg_prev
        add_actions [ " ", "[ ]continue", "/message/#{forum_id}/#{msg_prev}/backward" ]
      else
        add_actions [ " ", "[ ]continue", "/forum/#{forum_id}" ]
      end
      if msg_next
        add_actions [ "b", "[b]ack up", "/message/#{forum_id}/#{msg_next}/forward" ]
      else
        add_actions [ " ", "[b]ack up", "/forum/#{forum_id}" ]
      end
    end
    add_actions [ "q", "[q]uit", "/quit_from_forum/#{forum_id}" ]


    # this is one of the few times we don't have a separate
    # page for doing network stuff.

    threadingly do
      rescuingly do
        msg = get_message(forum_id, msgnum)
        body_urls = msg[:body].scan(URLRE)
        authority = " (#{msg[:authority]})" if msg[:authority]
        @whole_message = ( "#{msg[:date]} from #{msg[:author]}#{authority}\n" + 
                           "#{msg[:body]}" + 
                           "[#{@@forum_cache[forum_id][:name]}> msg #{msgnum} (#{ remaining } remaining)]")
        
        @page.clear do
          header_box
          section_box do
            para @whole_message
            body_urls.each do | a_url |
              para link(a_url, :click => a_url)
            end
          end
        end
      end
    end
    if @@forum_cache[forum_id][:first_unread] <= msgnum
      @@forum_cache[forum_id][:first_unread] = msgnum + 1
    end

  end

  def quit
    info "quit"
    exit()
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

  def mark_unread(forum_id,msgnum)
    forum_id = forum_id.to_i; msgnum = msgnum.to_i
    cache = @@forum_cache[forum_id]
    if msgnum < cache[:first_unread]
      cache[:first_unread] = msgnum
    end
    visit "/forum/#{forum_id}"
  end

  def new_reply(forum_id, msgnum)
    @page = page_box do
      "loading message #{msgnum} in forum #{forum_id} to reply to..."
    end

    threadingly do
      rescuingly do
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
          threadingly do
            rescuingly do
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


  # UTILITY METHODS
  
  def threadingly
    if @@use_threads
      Thread.new { yield }
    else
      yield
    end
  end

  def rescuingly
    debug "begin rescue block..."
    begin
      yield
    rescue Exception => err
      debug "rescuing #{err.message}"
      @@error = err
      visit '/error'
    end
    debug "end rescue block..."
  end

  # DISPLAY HELPER METHODS
  
  def page_box
    st = nil
    if @@config['white_bkg']
      background white
    else
      background black
    end
    stack  :margin => 20 do
      background(randcolor(:dark), :curve => 20)
      st = stack :margin => 20 do
        yield if block_given?
      end
    end
    st
  end

  def section_box
    st = nil
    stack :margin => 10 do
      background randcolor(:light, 0.5), :curve => 20
      st = stack :margin => 10 do
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
        background rgb(1.0, 1.0, 1.0, 0.5)..rgb(1.0, 1.0, 1.0, 0.2), :curve => 20
        caption text, :align => 'right', :stroke => randcolor(:realdark), :margin => 20
      end
      the_flow = flow :hidden => hidden do
        yield
      end
    end
  end

  def header_box(text = "")
    linklist ||= @action_links
    section_box do
      flow do
        flow( :width => -200) do
          para *action_links
        end
        flow( :width => 200) do
          tagline( text, :stroke => randcolor(:realdark), 
                   :margin => 20, :align => 'right')
        end
      end
    end
  end

  def option_box(text)
    the_check = nil
    chunk_box do
      flow do
        the_check = check { | me | yield me }
        para text
      end
    end
    the_check
  end

  def chunk_box
    stack :width => 200 do
      background rgb(1.0, 1.0, 1.0, 0.5)..rgb(1.0, 1.0, 1.0, 0.2), :curve => 10, :margin => 20
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
    r, g, b = [ ( (rand - 0.5) * range ) + target,
                ( (rand - 0.5) * range ) + target,
                ( (rand - 0.5) * range ) + target ]
    
    if @@config['gradients']
      rgb(r, g, b, alpha)..rgb(r, g, b, alpha * 0.3)
    else
      rgb(r, g, b, alpha)
    end
  end

  # BBS INTERACTION HELPER METHODS

  def recording_last_read(forum_id)
    if should_record_last_read(forum_id)
      clear do
        page_box do
          para "recording last read message..."
        end
      end
      threadingly do
        rescuingly do
          record_last_read(forum_id)
          yield
        end
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

  def get_message(forum_id, msgnum)
    msg = {}
    post = @@bbs.jump(forum_id).read(msgnum)
    [:date, :author, :body, :authority].each { |k| msg[k] = post.send(k) }
    msg[:message_id] = msgnum
    msg[:forum_id] = forum_id
    msg
  end

  # KEYBOARD INTERACTION HELPER METHODS
  
  def add_actions( *actions)
    @page_actions ||= []
    @page_actions = @page_actions + actions
  end
  
  def action_links
    @page_actions ||= []
    linklist = []
    @page_actions.each do | item |
      linklist << link(item[1], :click => item[2] )
      linklist << " " unless item == @page_actions.last
    end
    linklist
  end

  def setup_keypress
    @page_actions ||= []
    keypress do | key |
      found = @page_actions.assoc(key)
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
  end

end


Shoes.app :width => 850
