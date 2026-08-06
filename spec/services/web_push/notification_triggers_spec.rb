# frozen_string_literal: true

require 'rails_helper'

RSpec.describe WebPush::NotificationTriggers do
  describe '.agent_response' do
    let(:agent) { create(:agent, name: 'Research Bot') }
    let(:session) { create(:session, agent: agent, metadata: { 'started_by' => user.id }) }
    let(:user) { create(:user) }

    it 'sends a notification with truncated content' do
      allow(user).to receive(:notification_enabled?).with('agent_responses').and_return(true)
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notify)

      described_class.agent_response(session: session, content: 'Here is your summary')

      expect(user).to have_received(:notify).with(
        title: 'Research Bot',
        body: 'Here is your summary',
        url: "/m/sessions/#{session.id}",
        tag: "agent-response-#{session.id}"
      )
    end

    it 'broadcasts the same notification to the user notification channel stream' do
      allow(user).to receive(:notification_enabled?).with('agent_responses').and_return(true)
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notify)
      allow(ActionCable.server).to receive(:broadcast)

      described_class.agent_response(session: session, content: 'Here is your summary')

      expect(ActionCable.server).to have_received(:broadcast).with(
        "notifications_user_#{user.id}",
        hash_including(
          category: 'agent_responses',
          title: 'Research Bot',
          body: 'Here is your summary',
          tag: "agent-response-#{session.id}",
          session_id: session.id,
          agent_id: agent.id
        )
      )
    end

    it 'skips when user has agent_responses notifications disabled' do
      allow(user).to receive(:notification_enabled?).with('agent_responses').and_return(false)
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notify)

      described_class.agent_response(session: session, content: 'Hello')

      expect(user).not_to have_received(:notify)
    end

    it 'skips when no user found for session' do
      session.update!(metadata: { 'started_by' => -999 })
      allow(User).to receive(:find_by).with(id: -999).and_return(nil)

      expect { described_class.agent_response(session: session, content: 'Hello') }.not_to raise_error
    end
  end

  describe '.task_completed' do
    let(:user) { create(:user) }
    let(:parent_agent) { create(:agent, name: 'Orchestrator') }
    let(:child_agent) { create(:agent, name: 'POST Malone') }
    let(:parent_session) { create(:session, agent: parent_agent, metadata: { 'started_by' => user.id }) }
    let(:child_session) { create(:session, agent: child_agent) }
    let(:task) do
      create(:sub_agent_task,
        parent_agent: parent_agent,
        child_agent: child_agent,
        parent_session: parent_session,
        child_session: child_session,
        task: 'Post this tweet about Ruby dig patterns')
    end

    before do
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notification_enabled?).with('task_completions').and_return(true)
      allow(user).to receive(:notify)
    end

    it 'sends a notification with agent name and task description' do
      described_class.task_completed(task: task)

      expect(user).to have_received(:notify).with(
        title: 'Task Complete',
        body: 'POST Malone finished: Post this tweet about Ruby dig patterns',
        url: "/m/sessions/#{parent_session.id}",
        tag: "task-complete-#{task.id}"
      )
    end

    it 'truncates long task text to 80 characters' do
      task.update!(task: 'A' * 200)

      described_class.task_completed(task: task)

      expect(user).to have_received(:notify) do |args|
        expect(args[:body].length).to be <= 120 # agent name + " finished: " + 80 chars truncated
      end
    end

    it 'skips when user has task_completions disabled' do
      allow(user).to receive(:notification_enabled?).with('task_completions').and_return(false)

      described_class.task_completed(task: task)

      expect(user).not_to have_received(:notify)
    end

    it 'skips when parent_session is nil' do
      task.update_column(:parent_session_id, nil)
      task.reload

      expect { described_class.task_completed(task: task) }.not_to raise_error
    end

    it 'handles nil child_session gracefully' do
      task.update_column(:child_session_id, nil)
      task.reload

      described_class.task_completed(task: task)

      expect(user).to have_received(:notify) do |args|
        expect(args[:body]).to start_with(' finished:')
      end
    end
  end

  describe '.coding_task_done' do
    let(:user) { create(:user) }
    let(:agent) { create(:agent, name: 'Code Bot') }
    let(:session) { create(:session, agent: agent, metadata: { 'started_by' => user.id }) }

    it 'sends a notification for coding tasks' do
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notification_enabled?).with('task_completions').and_return(true)
      allow(user).to receive(:notify)

      # coding_task_done expects a task with .session, .agent, .description, .session_id
      coding_task = double(
        'CodingTask',
        id: 42,
        session: session,
        session_id: session.id,
        agent: agent,
        description: 'Refactor the authentication module'
      )

      described_class.coding_task_done(task: coding_task)

      expect(user).to have_received(:notify).with(
        title: 'Code Task Done',
        body: "Code Bot finished: Refactor the authentication module",
        url: "/m/sessions/#{session.id}",
        tag: 'coding-task-42'
      )
    end
  end

  describe '.budget_alert' do
    let(:prefs_enabled) { { 'budget_alerts' => true } }
    let(:prefs_disabled) { { 'budget_alerts' => false } }
    let(:agent) { create(:agent, name: 'Spender') }

    before { allow(WebPush::Sender).to receive(:call) }

    it 'notifies admin and owner users only' do
      admin = create(:user, :admin, notification_preferences: prefs_enabled)
      owner = create(:user, :owner, notification_preferences: prefs_enabled)
      _viewer = create(:user, :viewer, notification_preferences: prefs_enabled)

      described_class.budget_alert(agent: agent, percentage: 90)

      expect(WebPush::Sender).to have_received(:call).with(
        hash_including(
          user: admin,
          title: 'Budget Warning',
          body: 'Spender at 90% of daily limit'
        )
      )
      expect(WebPush::Sender).to have_received(:call).with(
        hash_including(user: owner, title: 'Budget Warning')
      )
      expect(WebPush::Sender).not_to have_received(:call).with(
        hash_including(user: _viewer)
      )
    end

    it 'skips users with budget_alerts disabled' do
      create(:user, :admin, notification_preferences: prefs_disabled)
      create(:user, :owner, notification_preferences: prefs_disabled)

      described_class.budget_alert(agent: agent, percentage: 90)

      expect(WebPush::Sender).not_to have_received(:call)
    end
  end

  describe '.heartbeat_finding' do
    before { allow(WebPush::Sender).to receive(:call) }

    it 'sends heartbeat notification to admin users' do
      create(:user, :admin, notification_preferences: { 'heartbeat_findings' => true })

      described_class.heartbeat_finding(finding_summary: 'Agent loop detected in session 42')

      expect(WebPush::Sender).to have_received(:call).with(
        hash_including(
          title: 'Heartbeat',
          body: 'Agent loop detected in session 42',
          url: '/m/activity'
        )
      )
    end

    it 'skips users with heartbeat_findings disabled' do
      create(:user, :admin, notification_preferences: { 'heartbeat_findings' => false })

      described_class.heartbeat_finding(finding_summary: 'Something happened')

      expect(WebPush::Sender).not_to have_received(:call)
    end
  end

  describe '.needs_input' do
    let(:agent) { create(:agent, name: 'Interviewer') }
    let(:user) { create(:user) }
    let(:session) { create(:session, agent: agent, metadata: { 'started_by' => user.id }) }
    let(:questions) { [ { 'question' => 'Which environment should I deploy to?' } ] }

    before do
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notify)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it 'notifies and broadcasts when needs_input is enabled' do
      allow(user).to receive(:notification_enabled?).with('needs_input').and_return(true)

      described_class.needs_input(session: session, questions: questions)

      expect(user).to have_received(:notify).with(
        title: 'Interviewer needs your input',
        body: 'Which environment should I deploy to?',
        url: "/m/sessions/#{session.id}",
        tag: "needs-input-#{session.id}"
      )
      expect(ActionCable.server).to have_received(:broadcast).with(
        "notifications_user_#{user.id}",
        hash_including(
          category: 'needs_input',
          title: 'Interviewer needs your input',
          body: 'Which environment should I deploy to?',
          tag: "needs-input-#{session.id}",
          session_id: session.id,
          agent_id: agent.id
        )
      )
    end

    it 'skips when the user has needs_input notifications disabled' do
      allow(user).to receive(:notification_enabled?).with('needs_input').and_return(false)

      described_class.needs_input(session: session, questions: questions)

      expect(user).not_to have_received(:notify)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end

    it 'skips when no user found for session' do
      session.update!(metadata: { 'started_by' => -999 })
      allow(User).to receive(:find_by).with(id: -999).and_return(nil)

      expect { described_class.needs_input(session: session, questions: questions) }.not_to raise_error
    end
  end

  describe '.session_error' do
    let(:agent) { create(:agent, name: 'Fragile Bot') }
    let(:user) { create(:user) }
    let(:session) { create(:session, agent: agent, metadata: { 'started_by' => user.id }) }

    before do
      allow(User).to receive(:find_by).with(id: user.id).and_return(user)
      allow(user).to receive(:notify)
      allow(ActionCable.server).to receive(:broadcast)
    end

    it 'notifies and broadcasts when errors notifications are enabled' do
      allow(user).to receive(:notification_enabled?).with('errors').and_return(true)

      described_class.session_error(session: session, message: 'Provider timed out')

      expect(user).to have_received(:notify).with(
        title: 'Fragile Bot hit an error',
        body: 'Provider timed out',
        url: "/m/sessions/#{session.id}",
        tag: "session-error-#{session.id}"
      )
      expect(ActionCable.server).to have_received(:broadcast).with(
        "notifications_user_#{user.id}",
        hash_including(
          category: 'errors',
          title: 'Fragile Bot hit an error',
          body: 'Provider timed out',
          tag: "session-error-#{session.id}",
          session_id: session.id,
          agent_id: agent.id
        )
      )
    end

    it 'skips when the user has errors notifications disabled' do
      allow(user).to receive(:notification_enabled?).with('errors').and_return(false)

      described_class.session_error(session: session, message: 'Provider timed out')

      expect(user).not_to have_received(:notify)
      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end
end
