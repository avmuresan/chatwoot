require 'google/cloud/dialogflow/cx/v3'

class Integrations::Dialogflow::ProcessorService < Integrations::BotProcessorService
  pattr_initialize [:event_name!, :hook!, :event_data!]

  private

  def message_content(message)
    # TODO: might needs to change this to a way that we fetch the updated value from event data instead
    # cause the message.updated event could be that that the message was deleted

    return message.content_attributes['submitted_values']&.first&.dig('value') if event_name == 'message.updated'

    message.content
  end

  def get_response(session_id, message)
    if hook.settings['credentials'].blank?
      Rails.logger.warn "Account: #{hook.try(:account_id)} Hook: #{hook.id} credentials are not present." && return
    end

    configure_dialogflow_client_defaults
    detect_intent(session_id, message)
  rescue Google::Cloud::PermissionDeniedError => e
    Rails.logger.warn "DialogFlow Error: (account-#{hook.try(:account_id)}, hook-#{hook.id}) #{e.message}"
    hook.prompt_reauthorization!
    hook.disable
  end

  def process_response(message, response)
    fulfillment_messages = response.query_result['response_messages']
    fulfillment_messages.each do |fulfillment_message|
      content_params = generate_content_params(fulfillment_message)
      if content_params['action'].present?
        process_action(message, content_params['action'])
      else
        create_conversation(message, content_params)
      end
    end
  end

  def generate_content_params(fulfillment_message)
    text_response = fulfillment_message['text'].to_h
    content_params = { content: text_response[:text].first } if text_response[:text].present?
    content_params ||= fulfillment_message['payload'].to_h
    content_params
  end

  def create_conversation(message, content_params)
    return if content_params.blank?

    conversation = message.conversation
    conversation.messages.create!(
      content_params.merge(
        {
          message_type: :outgoing,
          account_id: conversation.account_id,
          inbox_id: conversation.inbox_id
        }
      )
    )
  end

  def configure_dialogflow_client_defaults
    ::Google::Cloud::Dialogflow::CX::V3::Sessions::Client.configure do |config|
      config.timeout = 10.0
      config.credentials = hook.settings['credentials']
    end
  end

  def detect_intent(session_id, message)
    client = ::Google::Cloud::Dialogflow::CX::V3::Sessions::Client.new
    query_input = { text: { text: message }, language_code: 'en-US' }
    client.detect_intent session: session_path(session_id), query_input: query_input
  end

  def session_path(session_id)
    project_id = hook.settings['project_id']
    location = ENV.fetch('DIALOGFLOW_LOCATION', hook.settings.dig('credentials', 'location'))
    agent = ENV.fetch('DIALOGFLOW_AGENT', hook.settings.dig('credentials', 'agent'))
    path = "projects/#{project_id}/locations/#{location}/agents/#{agent}"

    environment = ENV.fetch('DIALOGFLOW_ENVIRONMENT', hook.settings.dig('credentials', 'environment'))
    path = "#{path}/environments/#{environment}" if environment.present?

    "#{path}/sessions/#{session_id}"
  end
end
