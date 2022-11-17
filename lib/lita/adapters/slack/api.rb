require 'faraday'

require 'lita/adapters/slack/exceptions'
require 'lita/adapters/slack/team_data'
require 'lita/adapters/slack/slack_im'
require 'lita/adapters/slack/slack_user'
require 'lita/adapters/slack/slack_source'
require 'lita/adapters/slack/slack_channel'

module Lita
  module Adapters
    class Slack < Adapter
      # @api private
      class API
        def initialize(config, stubs = nil)
          @config = config
          @stubs = stubs
          @post_message_config = {}
          @post_message_config[:parse] = config.parse unless config.parse.nil?
          @post_message_config[:link_names] = config.link_names ? 1 : 0 unless config.link_names.nil?
          @post_message_config[:unfurl_links] = config.unfurl_links unless config.unfurl_links.nil?
          @post_message_config[:unfurl_media] = config.unfurl_media unless config.unfurl_media.nil?
        end

        def im_open(user_id)
          response_data = call_api("conversations.open", user: user_id)

          SlackIM.new(response_data["channel"]["id"], user_id)
        end

        def channels_info(channel_id)
          call_api("channels.info", channel: channel_id)
        end

        def channels_list(params: {})
          conversations_list(types: ["public_channel"], params: params)
        end

        def users_list
          call_api("users.list")
        end

        def groups_list(params: {})
          response = conversations_list(types: ["private_channel"], params: params)
          response['groups'] = response['channels']
          response
        end

        def mpim_list(params: {})
          response = conversations_list(types: ["mpim"], params: params)
          response['groups'] = response['channels']
          response
        end

        def im_list(params: {})
          response = conversations_list(types: ["im"], params: params)
          response['ims'] = response['channels']
          response
        end

        def conversations_list(types: ["public_channel"], params: {})
          params.merge!({
            types: types.join(','),
            limit: 500, # reduce the number of paginated api requests we make (there are many channels)
          })
          call_paginated_api(method: 'conversations.list', params: params, result_field: 'channels')
        end

        def call_paginated_api(method:, params:, result_field:)
          retries = 0
          max_retries = 10

          begin
            retries += 1
            result = call_api(
              method,
              params
            )
          rescue RateLimitingError => e
            raise if retries > max_retries

            Lita.logger.debug("Rate-limited request to #{method}; retrying in #{e.response.headers['retry-after']}s")
            sleep(e.response.headers['retry-after'].to_i)
            retry
          end

          next_cursor = fetch_cursor(result)
          old_cursor = nil

          retries = 0
          while !next_cursor.nil? && !next_cursor.empty? && next_cursor != old_cursor
            retries += 1
            old_cursor = next_cursor
            params[:cursor] = next_cursor

            begin
              next_page = call_api(
                method,
                params
              )
            rescue RateLimitingError => e
              raise if retries > max_retries

              retry_delay = e.response.headers['retry-after'].to_i
              Lita.logger.debug("Rate-limited request to #{method}; retrying in #{retry_delay}s")
              sleep(retry_delay)
              old_cursor = nil
            else
              retries = 0
              next_cursor = fetch_cursor(next_page)
              result[result_field] += next_page[result_field]
            end
          end
          result
        end

        def send_attachments(room_or_user, attachments)
          call_api(
            "chat.postMessage",
            as_user: true,
            channel: room_or_user.id,
            attachments: MultiJson.dump(attachments.map(&:to_hash)),
          )
        end

        def open_dialog(dialog, trigger_id)
          call_api(
            "dialog.open",
            dialog: MultiJson.dump(dialog),
            trigger_id: trigger_id,
          )
        end

        def send_messages(channel_id, messages)
          call_api(
            "chat.postMessage",
            **post_message_config,
            as_user: true,
            channel: channel_id,
            text: messages.join("\n"),
          )
        end

        def reply_in_thread(channel_id, messages, thread_ts)
          call_api(
            "chat.postMessage",
            as_user: true,
            channel: channel_id,
            text: messages.join("\n"),
            thread_ts: thread_ts
          )
        end

        def delete(channel, ts)
          call_api("chat.delete", channel: channel, ts: ts)
        end

        def update_attachments(channel, ts, attachments)
          call_api(
            "chat.update",
            channel: channel,
            ts: ts,
            attachments: MultiJson.dump(attachments.map(&:to_hash))
          )
        end

        def set_topic(channel, topic)
          call_api("channels.setTopic", channel: channel, topic: topic)
        end

        def rtm_start
          channels = (
            SlackChannel.from_data_array(channels_list["channels"]) +
            SlackChannel.from_data_array(groups_list["groups"])
          )

          rtm_connect_response = call_api("rtm.connect")
          Lita.logger.debug("Start building rtm_start TeamData")
          team_data = TeamData.new(
            SlackIM.from_data_array(im_list["ims"]),
            SlackUser.from_data(rtm_connect_response["self"]),
            SlackUser.from_data_array(users_list["members"]),
            channels,
            rtm_connect_response["url"]
          )
          Lita.logger.debug("Done building rtm_start TeamData")

          team_data
        end

        private

        attr_reader :stubs
        attr_reader :config
        attr_reader :post_message_config

        def call_api(method, post_data = {})
          Lita.logger.debug("Making Slack API request: #{method}")
          response = connection.post(
            "https://slack.com/api/#{method}",
            { token: config.token }.merge(post_data)
          )
          Lita.logger.debug("Finished Slack API request: #{method}")
          data = parse_response(response, method)
          Lita.logger.debug("Finished parsing #{method} response")

          raise RateLimitingError.new('Slack API request rate-limited', response, data) if data['error'] == 'ratelimited'
          raise "Slack API call to #{method} returned an error: #{data["error"]}." if data["error"]

          data
        end

        def connection
          if stubs
            Faraday.new { |faraday| faraday.adapter(:test, stubs) }
          else
            options = {}
            unless config.proxy.nil?
              options = { proxy: config.proxy }
            end
            Faraday.new(options)
          end
        end

        def parse_response(response, method)
          unless response.status == 429 || response.success?
            raise "Slack API call to #{method} failed with status code #{response.status}: '#{response.body}'. Headers: #{response.headers}"
          end

          MultiJson.load(response.body)
        end

        def fetch_cursor(page)
          page.dig("response_metadata", "next_cursor")
        end
      end
    end
  end
end
