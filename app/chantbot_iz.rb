require 'http'
require 'json'
require 'eventmachine'
require 'faye/websocket'
require 'faraday'
require 'faraday_middleware'


class SlackBotAPI
  SLACK_API_POST_URL = 'https://slack.com/api/rtm.start'.freeze
  REPL_API_URL = 'https://api.repl-ai.jp'.freeze
  class << self

    def get_slack_rtm_url
      options = { params: { token: ENV["SLACK_API_TOKEN"] } }
      response = HTTP.post(SLACK_API_POST_URL, options)
      parse_body = JSON.parse(response.body)
      slack_rtm_url = parse_body['url']
      return slack_rtm_url
    end

    def socket_open
      EM.run do
        ws = Faye::WebSocket::Client.new(get_slack_rtm_url)
        ws.on :open do
          p [:open]
        end
        ws.on :message do |event|
          event_data = JSON.parse(event.data)
          puts event_data,"event_data"
          message = event_data['text']
          channelID = event_data['channel']
          unless message.nil?
            return_message = repl_send_message(message,channelID)
            ws.send(return_message)
          end
        end
        ws.on :close do
          EM.stop
        end
      end
    end

    def repl_send_message(slack_message,channelID)
      return_message = ({
        type: 'message',
        text: repl_get_message(slack_message),
        channel: channelID
      }.to_json)
      print_debug(slack_message)
      return return_message
    end

    # replからメッセージを取得
    def repl_get_message(slack_message,flag = false)
      res = post('/v1/dialogue',{
        appUserId: get_user_id,
        botId: ENV["REPLE_AI_BOTID"],
        voiceText: slack_message,
        initTalkingFlag: flag,
        initTopicId: ENV["REPLE_AI_SCENARIO"]
      })
      print_debug(res.body['systemText']['expression'])
      return res.body['systemText']['expression']
    end

    # POST faradayの初期化
    def faraday_init
      client = Faraday.new(:url => REPL_API_URL) do |conn|
        conn.request :json
        conn.response :json, :content_type => /\bjson$/
        conn.adapter Faraday.default_adapter
      end
      return client
    end

    def post(path,data)
      client = faraday_init
      res = client.post do |request|
        request.url path
        request.headers = {
            'Content-type' => 'application/json; charset=UTF-8',
            'x-api-key' => ENV["REPLE_AI_TOKEN"]
        }
        request.body = data
      end
      return res
    end

    # useridの取得
    def get_user_id
      res = post('/v1/registration',{
        botId: ENV['REPLE_AI_BOTID']
        })
      app_userid = res.body['appUserId']
      return app_userid
    end

    # debug用のメソッド
    def print_debug(messages)
      time = DateTime.now
      date_time = time.strftime("[%Y/%m/%d %H:%M:%S]")
      puts "#{date_time} message: #{messages}"
    end
  end
end

# ===========================================
# 実行
# ===========================================
SlackBotAPI.socket_open
