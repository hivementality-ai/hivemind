# Planning Mode Feature Documentation

## Overview

Planning Mode is a Claude Code-style planning feature that enables Hivemind agents to generate detailed work plans, display them to users, and execute them phase-by-phase. This feature helps agents tackle complex tasks by breaking them down into manageable phases with clear objectives, approaches, and success criteria.

## User Flow

### 1. Trigger Plan Generation

Users can generate a plan by using the `#plan` hashtag action:

```
#plan Build a user authentication system for my web app
```

Or simply:

```
#plan
```

If no task is provided with `#plan`, the agent will use the user's message content as the task description.

### 2. Plan Display

Once generated, the plan appears in the chat with:
- **Overview**: High-level description of the work
- **Context**: Relevant constraints and background
- **Phases**: Numbered, sequential phases with:
  - Name and number
  - Objectives (what needs to be accomplished)
  - Approach (how to accomplish it)
  - Tools needed (what resources are required)
  - Expected output (what success looks like for this phase)
- **Success Criteria**: Measurable markers of completion
- **Estimated Duration**: Time estimate for the entire plan

The plan is displayed as an expandable card in the chat UI, allowing users to see the overview at a glance and expand for detailed phase information.

### 3. Plan Execution

After the plan is displayed, the agent will:
1. Acknowledge the plan and begin execution
2. Start with Phase 1: [phase name]
3. Work through the objectives for the current phase
4. Report progress and results
5. Transition to the next phase with a clear marker: "Phase N: [phase name]"
6. Continue until all phases are complete

The agent has context about:
- The current phase (stored in session metadata)
- All phase objectives and approaches
- Success criteria to measure progress
- Which phase comes next

## Architecture

### Services

#### `Agents::PlanGenerator`

Generates structured work plans using the LLM. The service:
1. Resolves the model provider and adapter
2. Calls the LLM with a planning system prompt
3. Parses the JSON response into a structured plan
4. Validates the plan structure
5. Returns a `ServiceResponse` with the plan or error

**Input:**
- `agent`: The agent generating the plan
- `task`: Description of the task to plan
- `session`: Current session (optional, for context)

**Output:**
```ruby
{
  "overview" => "Brief summary",
  "context" => "Relevant context",
  "phases" => [
    {
      "number" => 1,
      "name" => "Phase name",
      "objectives" => ["obj1", "obj2"],
      "approach" => "How to do it",
      "tools_needed" => ["tool1", "tool2"],
      "expected_output" => "What success looks like"
    }
  ],
  "success_criteria" => ["criterion1", "criterion2"],
  "estimated_duration" => "2-3 hours"
}
```

#### `Tools::PlanModeExecutor`

Manages plan generation, execution, and phase tracking. Actions:

- **generate**: Creates a plan from a task description
  - Input: `action: "generate", task: "description"`
  - Calls `PlanGenerator` to create the plan
  - Stores plan in session metadata
  - Broadcasts plan to UI
  - Returns plan in response data

- **execute**: Starts plan execution
  - Input: `action: "execute"`
  - Sets plan status to "executing"
  - Sets current phase to 1
  - Broadcasts execution start to UI

- **update_phase**: Transitions to the next phase
  - Input: `action: "update_phase", phase_number: N`
  - Updates current phase in session metadata
  - Broadcasts phase update to UI
  - Validates phase number is within range

#### `HashtagActions::Actions::Plan`

Hashtag action that triggers plan generation via `#plan`:

1. Extracts the task from the payload or clean message
2. Calls the `plan_mode` tool with `generate` action
3. Formats the plan for display
4. Builds phase context for the agent's system prompt
5. Returns formatted response and prompt addon

## UI Components

### Plan Display Card

The plan is displayed as a collapsible card in the chat:

```
📋 Work Plan [Show Details]
├── Overview: Brief summary
├── Context: Relevant details
├── Phases:
│   ├── 1. Phase Name
│   ├── 2. Phase Name
│   └── 3. Phase Name
├── Success Criteria: criterion1; criterion2
└── Estimated Duration: 2-3 hours
```

Clicking "Show Details" expands to show:
- Full objectives for each phase
- Complete approach descriptions
- All tools needed
- Expected outputs

### Plan Execution Indicators

When execution starts:
- Progress indicator showing current phase / total phases
- Progress bar updating as phases complete
- Phase transition messages with phase number and name

### Phase Markers

In the chat, phase transitions appear as:

```
📍 Phase N: Phase Name
├── Objectives: objective1; objective2
└── Approach: Description of how to accomplish
```

## JavaScript Integration

### Chat Controller Updates

The `chat_controller.js` handles plan messages:

```javascript
handleMessage(data) {
  case "plan":
    this.handlePlanMessage(data)
    break
}

handlePlanMessage(data) {
  const { action, plan, current_phase, total_phases, phase_data } = data
  
  switch (action) {
    case "display":
      this.displayPlan(plan)
      break
    case "start_execution":
      this.displayPlanExecution(plan, current_phase, total_phases)
      break
    case "phase_update":
      this.updatePhaseDisplay(current_phase, total_phases, phase_data)
      break
  }
}
```

### Plan Display Methods

- `displayPlan(plan)`: Renders the initial plan card
- `displayPlanExecution(plan, phase, total)`: Shows execution start
- `updatePhaseDisplay(phase, total, data)`: Updates on phase transition
- `togglePlanDetails(event)`: Toggles detail visibility

## Session Metadata

Plan information is stored in session metadata for agent context:

```ruby
session.metadata = {
  "current_plan" => { plan JSON },
  "plan_generated_at" => "2024-01-15T10:30:00Z",
  "plan_status" => "generated|executing|completed",
  "current_phase" => 1,
  "plan_started_at" => "2024-01-15T10:35:00Z"
}
```

## System Prompt Integration

When a plan is generated, the `Plan` hashtag action injects phase context into the agent's system prompt:

```
User has created a multi-phase plan:
Phase 1 (Setup): objectives...
Phase 2 (Build): objectives...
Phase 3 (Test): objectives...

You will execute this plan phase by phase:
1. Start each phase with a clear marker: "## Phase N: [name]"
2. Execute the objectives for the current phase
3. Track your progress and show what you've accomplished
4. When ready, move to the next phase

You can reference the plan whenever needed to stay on track.
```

This context helps the agent understand it should:
- Reference the plan structure
- Follow phases sequentially
- Use clear phase markers
- Track progress for each phase
- Move systematically through the work

## Implementation Example

### User initiates planning:

```
User: #plan Build a REST API with authentication
```

### Agent generates plan:

The `#plan` hashtag action:
1. Calls `Tools::PlanModeExecutor` with `action: "generate"`
2. PlanExecutor calls `Agents::PlanGenerator`
3. Generator sends planning prompt to LLM
4. LLM returns structured plan JSON
5. Plan is stored in session and broadcast to UI

### Chat displays plan:

```
📋 Work Plan [Show Details]
└── 3 Phases: Setup, Build API, Add Auth
```

### Agent begins execution:

The agent's system prompt now includes phase context. It executes Phase 1:

```
Agent: ## Phase 1: Setup
I'll start by setting up the project structure...
[Agent performs Phase 1 work]
Complete. Ready for Phase 2.
```

### User can request phase transition:

Users or the agent can trigger `update_phase` to move to the next phase:

```
Agent: ## Phase 2: Build API
Now I'll implement the REST endpoints...
[Agent performs Phase 2 work]
```

## Error Handling

### Plan Generation Failures

If plan generation fails:
- LLM returns invalid/incomplete JSON → Agent retries
- Provider resolution fails → Error message to user
- Parsing fails → User asked to clarify task

### Phase Validation

- Invalid phase numbers rejected with validation error
- Phase number must be 1 to N (total phases)
- Cannot execute without an active plan

### Broadcast Failures

If ActionCable broadcast fails:
- Plan still stored in session metadata
- Agent continues with plan execution
- UI may need refresh to see latest state

## Testing

### Unit Tests

- `PlanGeneratorSpec`: Tests plan generation and parsing
- `PlanModeExecutorSpec`: Tests generate/execute/update_phase actions
- `PlanActionSpec`: Tests hashtag action integration

### Integration Tests

- `planning_mode_spec.rb`: End-to-end plan workflow

### Test Coverage

```ruby
# Test plan generation with various LLM responses
# Test plan structure validation
# Test phase tracking and validation
# Test hashtag action formatting
# Test broadcast to UI
# Test error handling and recovery
```

## Configuration

### Environment Variables

No additional environment variables required. Uses existing:
- `RAILS_ENV` for environment
- `LLM_MODEL` for model selection (inherited from agent)

### Tool Definition

The `plan_mode` tool is defined in `db/seeds/tools.rb`:

```ruby
{
  name: "plan_mode",
  description: "Generate, manage, and execute multi-phase work plans",
  executor_type: "plan_mode",
  requires_approval: false,
  parameters_schema: {
    "properties" => {
      "action" => {
        "type" => "string",
        "enum" => ["generate", "execute", "update_phase"]
      },
      "task" => { "type" => "string", "description" => "Task to plan" },
      "phase_number" => { "type" => "integer", "description" => "Phase to move to" }
    },
    "required" => ["action"]
  }
}
```

## Future Enhancements

Potential improvements for planning mode:

1. **Plan Persistence**: Save plans to database for later retrieval
2. **Plan Templates**: Pre-defined plan templates for common tasks
3. **Collaborative Planning**: Multiple agents/users contribute to plan
4. **Plan Visualization**: Gantt charts or timeline views
5. **Adaptive Plans**: Agent can modify plan based on progress
6. **Plan Checkpoints**: Save progress state at each phase
7. **Plan Variations**: Generate alternative approaches
8. **Plan Metrics**: Track time vs. estimates, completion rate

## Troubleshooting

### Plan not generating

- Check LLM provider is configured
- Verify agent has access to plan_mode tool
- Check task description is clear and specific
- Review LLM logs for parsing errors

### Phases not tracking correctly

- Ensure session metadata is being saved
- Check current_phase value in session.metadata
- Verify phase numbers are sequential

### UI not displaying plan

- Check browser console for JavaScript errors
- Verify ActionCable connection is active
- Check plan JSON structure is valid

### Agent not following plan

- Ensure phase context is in system prompt
- Verify agent has clear phase transition markers
- Check that session metadata includes current plan

## References

- Claude Code documentation: https://docs.anthropic.com/
- Rails ActionCable: https://guides.rubyonrails.org/action_cable_overview.html
- Service Response pattern: Used throughout Hivemind
- Tool Loop: `app/services/agents/tool_loop.rb`
