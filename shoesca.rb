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

  STACKSTYLE = { :width => 650, :margin => 20 }
  URLRE = Regexp.new('https?://[^ \n\)]+')
 
  url '/', :main
  url '/forums', :forums
  url '/login', :login
  url '/license', :license
  url '/forum/(\d+)', :forum
  url '/foruminfo/(\d+)', :foruminfo
  url '/first_todo', :first_todo
  url '/first_unread/(\d+)', :first_unread
  url '/message/(\d+)/(\d+)', :message
  url '/mark_unread/(\d+)/(\d+)', :mark_unread
  url '/new_post/(\d+)', :new_post
  url '/new_reply/(\d+)/(\d+)', :new_reply
  @@bbs = nil


  def license
    stack STACKSTYLE do
      background aliceblue, :curve => 20
      border black, :curve => 20
      para link('back', :click => '/login')
      para LICENSE
    end
  end

  def login
    @store = YAML::Store.new('bbsconfig.yaml')
    @username, @password = nil, nil
    @store.transaction(true) do
      @username, @password = @store['username'], @store['password']
    end

    def do_login
      @username = @username_line.text
      @password = @password_line.text
      @mainstack.append do
        para "logging in..."
      end
      Thread.new do
        begin
          @@bbs = Raccdoc::Connection.new(:user => @username, :password => @password,
                                          :host => '64.198.88.46', # bbs.iscabbs.com was not resolving
                                          :port => 6145
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

  def main
    if @@bbs
      visit '/forums'
    else
      visit '/login'
    end
  end

  def forums
    visit '/login' unless @@bbs

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
            ordered_ids.each do | id |
              data = forums[id]
              stack STACKSTYLE do
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
  
  def forum(id)
    visit '/login' unless @@bbs
    linklist, keypressproc = actions( [[ 'p', '[p]ost', "/new_post/#{id}"],
                                       [ 'i', '[i]nfo', "/foruminfo/#{id}"],
                                       [ 'i', '[b]ack to forum list', "/forums"],
                                       [ ' ', '[ ]first unread', "/first_unread/#{id}"],
                                       [ 'q', '[q]uit', Proc.new { exit() } ]
                                      ] )
    
    keypress { | key |  keypressproc.call(key) }
    
    @mainstack = stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "loading forum #{id}..."
    end

    Thread.new {
      @forum = @@bbs.jump(id)
      first_unread = @forum.first_unread.to_i
      @posts = @forum.post_headers
      noteids = @forum.noteids.sort
      msgs_unread = noteids.select { |msg| msg.to_i >= first_unread }
      msgs_read = noteids.select { |msg| msg.to_i < first_unread }
      info "got posts"
      @mainstack.clear do
        info "adding background"
        background blanchedalmond, :curve => 20
        border black, :curve => 20
        para *linklist
        [ [ "Unread", msgs_unread,  ],
          [ "Read", msgs_read,  ]].each do | pair |
          group_name, ordered_ids = *pair
          info "adding #{group_name} stack"
          stack STACKSTYLE do
            background white, :curve => 20
            border black, :curve => 20
            caption group_name
            ordered_ids.each do | post_id |
              post = @posts[post_id.to_s]
              stack STACKSTYLE do
                background ivory, :curve => 10
                border black, :curve => 10
                para link("#{ post_id }/#{post[:author]}/#{post[:date]}/#{post[:size]}", :click => "/message/#{id}/#{post_id}")
                para post[:subject]
              end
            end
          end
        end
      end
    }
  end

  def foruminfo(id)
    visit '/login' unless @@bbs
    @forum = @@bbs.jump(id)

    linklist, keypressproc = actions [[ 'b', '[b]ack', "/forum/#{id}"],
                                      [ 'p', '[p]ost', "/new_post/#{id}"],
                                      [ " ", "[ ]first unread message", "/first_unread/#{id}" ],
                                     ]
    keypress { | key |  keypressproc.call(key) }
    
    stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      tagline( link(link("Forums", :click => "/forums")), " / ", 
               link( "#{@forum.name}>", :click => "/forum/#{id}") )
      para *linklist
      @info = @forum.forum_information
      stack STACKSTYLE do
        background lightgrey, :curve => 10
        border black, :curve => 10
        caption "Forum moderator is #{@forum.admin}.  Total messages: #{@forum.noteids.last}."
        caption "Forum info last updated #{@info[:date]} by Mikemike"
        para "#{@info[:body]}"
      end
    end
  end

  def first_todo
    stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "finding first forum with unread messages..."
    end
    forums_todo = (@@bbs.forums('todo').to_a.map{ |k| k[0] } - [1]).sort
    if forums_todo.length > 0
      forum_id = forums_todo[0]
      info "found todo forum: #{forum_id}"
      visit "/first_unread/#{forum_id}"
    else
      info "found no todo forums: visiting forums"
      visit "/forums"
    end
  end

  def first_unread(forum_id)
    visit '/login' unless @@bbs
    info "first_unread for forum_id #{forum_id}"

    stack STACKSTYLE do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      para "finding first unread message in forum #{forum_id}..."
    end
    Thread.new {
      if forum_id.length == 0 # need to find it
        info "zero length forum id, looking for first unread forum"
      end
      info "jumping to #{forum_id}"
      @forum =  @@bbs.jump(forum_id)
      info "finding first unread"
      first_unread_msg = @forum.first_unread.to_i
      info "seeing if it exists"
      first_unread_found = @forum.noteids.sort.detect { |noteid| noteid >= first_unread_msg }
      if first_unread_found
        info "visiting it"
        visit "/message/#{forum_id}/#{first_unread_found}"
      else
        info "visiting first todo"
        visit "/first_todo"
      end
    }
  end

  def mark_unread(forum_id,msgnum)
    visit '/login' unless @@bbs
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

  def message(forum_id,msgnum)
    visit '/login' unless @@bbs
    stack STACKSTYLE do
      background gold, :curve => 20
      border black, :curve => 20
      @messagestack = stack { para "loading message #{msgnum} in forum #{forum_id}..." }
    end

    Thread.new {
      @forum =  @@bbs.jump(forum_id)
      first_unread_msg = @forum.first_unread.to_i
      if msgnum.to_i >= first_unread_msg
        @forum.first_unread = msgnum.to_i + 1
      end
      post_ids = @forum.post_headers.keys.sort.reverse
      post_index = post_ids.index(msgnum)
      msg_prev = post_ids[post_index + 1] if post_index < (post_ids.length - 1)
      msg_next = post_ids[post_index - 1] if post_index > 0
      @post = @forum.read(msgnum)

      action_list = 
      if msg_prev;[[ "p", "[p]revious", "/message/#{forum_id}/#{msg_prev}"]]; else []; end +
      if msg_next; [[ "n", "[n]ext","/message/#{forum_id}/#{msg_next}" ]]; else []; end +
      [ [ "r" , "[r]eply",  "/new_reply/#{forum_id}/#{msgnum}" ],
        [ "b" , "[b]ack to forum", "/forum/#{forum_id}" ],
        [ "u", "mark [u]nread", "/mark_unread/#{forum_id}/#{msgnum}" ],
        [ "c", "[c]opy to clipboard",  Proc.new { self.clipboard=@whole_message; alert( "Copied to clipboard.") } ],
        [ " ", "[ ]first unread message", "/first_unread/#{forum_id}" ],
        [ "q", "[q]uit", Proc.new { exit()} ] ]
      
      linklist, keypressproc = actions(action_list)
      keypress { | key |  
        keypressproc.call(key) 
      }

      the_body = @post.body
      body_urls = the_body.scan(URLRE)

      @messagestack.clear do
        para *linklist
        @whole_message = "#{@post.date} from #{@post.author}\n#{the_body}[#{@forum.name}> msg #{msgnum} (#{ post_index } remaining)]"
        
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
    visit '/login' unless @@bbs
    @post = @@bbs.jump(forum_id).read(msgnum)
    old_body = @post.body.split("\n").map{ |line| "> #{line}" }.join("\n")
    quote = "#{@post.author} wrote:\n#{old_body}\n\n"
    stack STACKSTYLE do
      background lime, :curve => 20
      border black, :curve => 20
      tagline "New Post"
      para link("back", :click => "/message/#{forum_id}/#{msgnum}")
      @post_box = edit_box quote, :width => 500, :height => 300
      button "post" do
        text = @post_box.text
        new_post = @@bbs.jump(forum_id).post(text)
        visit("/message/#{forum_id}/#{new_post.id}")
      end
    end
  end
  
  def new_post(forum_id)
    visit '/login' unless @@bbs
    stack STACKSTYLE do
      background lime, :curve => 20
      border black, :curve => 20
      tagline "New Post"
      para link("back", :click => "/forum/#{forum_id}")
      @post_box = edit_box :width => 500, :height => 300
      button "post" do
        text = @post_box.text
        new_post = @@bbs.jump(forum_id).post(text)
        visit("/message/#{forum_id}/#{new_post.id}")
      end
    end
  end
end

Shoes.app :width => 800
