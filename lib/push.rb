class Pushie

  def self.send(user, msg, data={}) 
    client = HTTPClient.new
    devices = SQL[:devices].where(:user_id => user[:id])
    devices.each do |device|
      if ['apns_production','apns_sandbox'].include? device[:token_type]

        puts "Sending push to #{user[:username]} (#{device[:token]})"

        if msg
          notification = {
            alert: msg,
            sound: 'default'
          }.merge(data)
        else
          notification = data
        end

        jj notification

        client.post "#{SiteConfig['pushlet']}/message/apn", {
          appId: 'coffeetime.io',
          deviceId: device[:token],
          mode: device[:token_type].gsub(/apns_/,''),
          cert: File.open('./lib/push.cert', 'rb') { |f| f.read },
          key: File.open('./lib/push.key', 'rb') { |f| f.read },
          notification: notification,
          timeout: 1000
        }.to_json, {
          'Content-Type' => 'application/json'
        }
      end
    end
  end

end