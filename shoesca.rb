Shoes.setup do
  Gem.sources = ['http://gems.github.com/', 'http://gems.rubyforge.org/']
  gem 'minter-raccdoc'
end

require 'raccdoc'
require 'yaml/store'

class RaccdocClient < Shoes

  url '/', :main
  url '/login', :login
  url '/forum/(\d+)', :forum
  url '/message/(\d+)/(\d+)', :message
  url '/new_post/(\d+)', :new_post
  url '/new_reply/(\d+)/(\d+)', :new_reply
  @@bbs = nil

  def login
    store = YAML::Store.new('bbsconfig.yaml')
    username, password = nil, nil
    store.transaction(true) do
      username, password = store['username'], store['password']
    end

    stack :width => 700, :margin => 50 do
      background salmon, :curve => 20
      border black, :curve => 20
      title "Login"
      para "username:"
      @username_line = edit_line "#{ username }"
      para "password:"
      @password_line = edit_line "#{ password }", :secret => true
      button "login" do
        username = @username_line.text
        password = @password_line.text
        store.transaction do
          store['username'], store['password'] = username, password
        end
        @@bbs = Raccdoc::Connection.new(:user => username, :password => password)
        visit '/'
      end
    end
  end

  def main
    visit '/login' unless @@bbs
    stack :width => 700, :margin => 50 do
      background aliceblue, :curve => 20
      border black, :curve => 20
      title "Forums"
      forums = @@bbs.forums
      ordered_ids = forums.keys.sort { |a,b| forums[a][:name] <=> forums[b][:name] }
      ordered_ids.each do | id |
        data = forums[id]
        stack :width => 0.90, :margin => 3 do
          background lightgrey, :curve => 10
          border black, :curve => 10
          para link("#{id}> #{data[:name]}", :click => "/forum/#{id}")
#          para "#{data.inspect}"
        end
      end
    end
  end

  def forum(id)
    visit '/login' unless @@bbs
    @forum = @@bbs.jump(id)
    stack :width => 700, :margin => 50 do
      background blanchedalmond, :curve => 20
      border black, :curve => 20
      title "#{@forum.name}>"
      para "Admin is #{@forum.admin}."
      para( link("back", :click => "/"),
            " ",
            link("post", :click => "/new_post/#{id}") )
      @posts = @forum.post_headers
      @post_ids = @posts.keys.sort.reverse
      @post_ids.each do | post_id |
        post = @posts[post_id]
        stack :width => 0.90 do
          background lightgrey, :curve => 10
          border black, :curve => 10
          para link("#{ post_id }/#{post[:author]}/#{post[:date]}/#{post[:size]}", :click => "/message/#{id}/#{post_id}")
          para post[:subject]
        end
      end

    end
  end

  def message(forum_id,msgnum)
    visit '/login' unless @@bbs
    @forum =  @@bbs.jump(forum_id)
    post_ids = @forum.post_headers.keys.sort.reverse
    post_index = post_ids.index(msgnum)
    msg_prev = post_ids[post_index + 1] if post_index < (post_ids.length - 1)
    msg_next = post_ids[post_index - 1] if post_index > 0
    info post_ids.inspect
    info msgnum
    info msg_prev
    info msg_next
    @post = @forum.read(msgnum)
    stack :width => 700, :margin => 50 do
      background gold, :curve => 20
      border black, :curve => 10
      title "Message"
      tagline "#{@post.date} from #{@post.author}"
      para @post.body
      tagline "[#{@forum.name}> msg #{msgnum} (#{ post_index } remaining)]"
      para( if msg_next; link("next", :click => "/message/#{forum_id}/#{msg_next}"); end,
            " ",
            if msg_prev; link("previous", :click => "/message/#{forum_id}/#{msg_prev}"); end,
            " ",
            link("forum", :click => "/forum/#{forum_id}"),
            " ",
            link("reply", :click => "/new_reply/#{forum_id}/#{msgnum}") )
      
#      para @post.inspect
    end
  end

  def new_reply(forum_id, msgnum)
    visit '/login' unless @@bbs
    @post = @@bbs.jump(forum_id).read(msgnum)
    old_body = @post.body.split("\n").map{ |line| "> #{line}" }.join("\n")
    quote = "#{@post.author} wrote:\n#{old_body}\n\n"
    stack :width => 700, :margin => 50 do
      background lime, :curve => 20
      border black, :curve => 10
      title "New Post"
      para link("back", :click => "/forum/#{forum_id}")
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
    stack :width => 700, :margin => 50 do
      background lime, :curve => 20
      border black, :curve => 10
      title "New Post"
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
