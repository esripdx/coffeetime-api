Dir.glob(['controllers','lib'].map! {|d| File.join d, '*.rb'}).each do |f| 
  require_relative f
end


class App < Jsonatra::Base

  set_up_actors do
    @@pushie = Pushie.new 
    @@callback = Callback.new
    @@group_updater = GroupUpdater.new
  end

  configure do
    set :arrayified_params, [:keys]
  end

  def require_auth
    header_error :authorization, 'missing', 'Authorization header required' if request.env['HTTP_AUTHORIZATION'].nil? or request.env['HTTP_AUTHORIZATION'].empty?
    halt if response.error?

    auth = request.env['HTTP_AUTHORIZATION'].match /Bearer (.+)/
    header_error :authorization, 'invalid', 'Bearer authorization header required' if auth.nil?
    halt if response.error?

    access_token = auth[1]
    begin
      @token = JWT.decode(access_token, SiteConfig['secret'])
      # puts "Auth: #{@token.inspect}"
    rescue 
      header_error :authorization, 'invalid', 'Access token was invalid'
    end
    halt if response.error?

    Octokit.auto_paginate = true
    @github = Octokit::Client.new :access_token => @token['github_access_token']

    @user = SQL[:users].first :id => @token['user_id']

    @token
  end

  def require_group
    param_error :group_id, 'missing', 'group_id required' if params['group_id'].blank?
    halt if response.error?

    # Check if the group exists
    @group = SQL[:groups].first :id => params['group_id']
    param_error :group_id, 'invalid', 'group_id not found' if @group.nil?
    halt if response.error?

    # Check if the user is a member of the group
    @membership = get_membership(@group[:id], @user[:id]).first
    param_error :group_id, 'forbidden', 'user not a member of this group' if @membership.nil?
    halt if response.error?

    # Mark the group as active and cache the user's github token for the group
    # so that the cron job has a Github access token it can use when running outside
    # the context of a user.
    SQL[:groups].where(:id => @group[:id]).update({
      :last_active_date => DateTime.now,
      :last_active_github_token => @token['github_access_token']
    })

    # Cache users being returned in a list
    # This also clears the cache between each request
    @users = {}
  end

  def timezone_from_param
    begin
      if params['timezone']
        timezone = Timezone::Zone.new :zone => params['timezone']
      elsif params['timezone_offset']
        zone = Timezone.offset_to_zone(params['timezone_offset'].to_i)
        if zone
          timezone = Timezone::Zone.new(:zone => zone)
        else
          param_error :timezone, 'invalid', 'No timezone was found for the given offset'
        end
      end
    rescue Timezone::Error::InvalidZone
      param_error :timezone, 'invalid', 'Invalid timezone specified'
    rescue => e
      puts "TIMEZONE ERROR"
      puts e.inspect
      param_error :timezone, 'invalid', 'Something went horribly wrong'
    end
  end

  def group_balance(group_id)
    SQL[:memberships].select(Sequel.function(:max, :balance), Sequel.function(:min, :balance)).where(:group_id => group_id).first
  end

  def get_membership(group_id, user_id) 
    SQL[:memberships].where(:group_id => group_id, :user_id => user_id)
  end

  def get_transaction(transaction_id, tz)
    query = SQL[:transactions].select(Sequel.lit('*, ST_Y(location::geometry) AS latitude, ST_X(location::geometry) AS longitude'))
      .where(:id => transaction_id)

    query.map do |t|
      format_transaction(t, tz)
    end
  end

  def get_recent_transactions(group_id, user_id, tz, limit=20)
    query = SQL[:transactions].select(Sequel.lit('*, ST_Y(location::geometry) AS latitude, ST_X(location::geometry) AS longitude'))
      .where(:group_id => group_id).where(Sequel.or(:from_user_id => user_id, :to_user_id => user_id)).order(Sequel.desc(:date)).limit(limit)

    query.map do |t|
      format_transaction(t, tz)
    end
  end

  def get_transactions(group_id, tz, opts={})
    # opts: before_id, after_id, limit

    query = SQL[:transactions].select(Sequel.lit('*, ST_Y(location::geometry) AS latitude, ST_X(location::geometry) AS longitude'))
      .where(:group_id => group_id)

    if opts[:before_id]
      query = query.where{id < opts[:before_id]}
    end
    if opts[:after_id]
      query = query.where{id > opts[:after_id]}
    end

    query = query.order(Sequel.desc(:date)).limit(opts[:limit]||20)

    query.map do |t|
      format_transaction(t, tz, false)
    end
  end

  def format_date(date, tz)
    if date
      timezone = Timezone::Zone.new :zone => tz
      date.to_time.localtime(timezone.utc_offset).iso8601
    else
      nil
    end
  end

  def format_transaction(transaction, tz, use_logged_in_user=true)
    if @users[transaction[:from_user_id]].nil?
      @users[transaction[:from_user_id]] = SQL[:users].first :id => transaction[:from_user_id]
    end
    if @users[transaction[:to_user_id]].nil?
      @users[transaction[:to_user_id]] = SQL[:users].first :id => transaction[:to_user_id]
    end

    from = @users[transaction[:from_user_id]]
    to = @users[transaction[:to_user_id]]

    summary = "#{(use_logged_in_user and from[:id] == @user[:id]) ? 'You' : from[:display_name]} bought #{transaction[:amount]} coffee#{transaction[:amount] == 1 ? '' : 's'} for #{(use_logged_in_user and to[:id] == @user[:id]) ? 'you' : to[:display_name]}"

    {
      transaction_id: transaction[:id],
      date: format_date(transaction[:date], tz),
      from_user_id: transaction[:from_user_id],
      to_user_id: transaction[:to_user_id],
      amount: transaction[:amount],
      note: transaction[:note],
      created_by: transaction[:created_by],
      latitude: transaction[:latitude],
      longitude: transaction[:longitude],
      accuracy: transaction[:accuracy],
      location_date: format_date(transaction[:location_date], tz),
      summary: summary
    }
  end

  def format_user(user, group=nil, membership=nil)
    if group
      g_balance = group_balance(group[:id])
      balance = {
        user_balance: membership[:balance],
        max_balance: g_balance[:max],
        min_balance: g_balance[:min],
        active: membership[:active]
      }
    else
      balance = {}
    end

    {
      user_id: user[:id],
      username: user[:username],
      display_name: user[:display_name],
      avatar_url: user[:avatar_url]
    }.merge(balance)
  end

  get '/' do
    {
      hello: 'world'
    }
  end

end
