class Pushie

  def self.send(user, msg, data={}) 
    client = HTTPClient.new
    devices = SQL[:devices].where(:user_id => user[:id])
    devices.each do |device|
      if ['apns_production','apns_sandbox','gcm'].include? device[:token_type]

        puts "Sending push to #{user[:username]} (#{device[:token_type]} #{device[:token]})"

        if device[:token_type] == 'gcm'
          path = "gcm"
          provider = {
            mode: 'production',
            key: File.open('./lib/gcm.key', 'rb') { |f| f.read }
          }
        else
          path = "apn"
          provider = {
            mode: device[:token_type].gsub(/apns_/,''),
            cert: File.open('./lib/push.cert', 'rb') { |f| f.read },
            key: File.open('./lib/push.key', 'rb') { |f| f.read }
          }
        end

        if msg
          notification = {
            alert: msg,
            sound: 'default'
          }.merge(data)
        else
          notification = data
        end

        jj notification

        client.post "#{SiteConfig['pushlet']}/message/#{path}", {
          appId: 'coffeetime.io',
          deviceId: device[:token],
          notification: notification,
          timeout: 1000
        }.merge(provider).to_json, {
          'Content-Type' => 'application/json'
        }
      end
    end
  end

end