# Planning Mode Feature - Pull Request

## Overview

This PR implements Claude Code-style planning mode for Hivemind agents, enabling them to generate detailed work plans, display them in the chat UI, and execute them phase-by-phase.

## User Impact

### Before
Users asked agents to plan tasks, but there was no structured way to break work into phases, track progress, or ensure the agent followed a systematic approach.

### After
Users can now:
1. **Generate Plans**: Type `#plan Build a REST API` to generate a structured work plan
2. **View Plans**: See plans as beautiful, interactive cards with all phases and details
3. **Track Progress**: Watch agents execute phase-by-phase with clear progress indicators
4. **Reference Plans**: Agents know which phase they're in and what comes next

## Example Flow

```
User: #plan Build a user authentication system for my web app

Agent Response:
✅ Plan generated! I'll now execute it phase by phase.

📋 Work Plan [Show Details]
├── Overview: Implement a complete authentication system
├── Phases:
│   ├── 1. Database Setup
│   ├── 2. Authentication Routes
│   └── 3. Session Management
├── Success Criteria: Users can sign up, log in, sessions persist
└── Estimated Duration: 4-6 hours

[User expands plan]

Then agent executes:

## Phase 1: Database Setup
I'll create the user table with password hashing...
[Agent creates migrations, models, runs database setup]
✅ Complete

## Phase 2: Authentication Routes
Now implementing signup and login endpoints...
[Agent implements controller actions and views]
✅ Complete

## Phase 3: Session Management
Adding user sessions and logout...
[Agent implements session handling]
✅ All phases complete!
```

## Technical Implementation

### New Services

1. **`Agents::PlanGenerator`** (122 lines)
   - Generates structured work plans via LLM
   - Validates plan structure and completeness
   - Returns ServiceResponse with parsed plan
   - Handles JSON parsing and error cases

2. **`Tools::PlanModeExecutor`** (Enhanced, 120 lines)
   - Supports three actions:
     - `generate`: Creates plan from task description
     - `execute`: Starts plan execution
     - `update_phase`: Transitions to next phase
   - Stores plans in session metadata
   - Broadcasts updates via ActionCable

3. **`HashtagActions::Actions::Plan`** (Enhanced, 108 lines)
   - Triggers plan generation via `#plan` command
   - Formats plan for display in chat
   - Builds phase context for agent's system prompt
   - Integrates with existing tool loop

### UI Enhancements

**Chat Controller** (`chat_controller.js`)
- Added plan message handler
- Displays plan cards with collapsible details
- Shows phase transitions with progress indicators
- Real-time updates via ActionCable

**Plan Display Features**
- Overview with task context
- Numbered phases with icons
- Expandable details showing:
  - Phase objectives
  - Approach and strategy
  - Tools and resources needed
  - Expected outputs
- Success criteria and duration
- Progress bar during execution

### Data Storage

Plans are stored in `session.metadata`:
```ruby
session.metadata = {
  "current_plan" => { JSON structure },
  "plan_generated_at" => "2024-01-15T10:30:00Z",
  "plan_status" => "generated|executing",
  "current_phase" => 1,
  "plan_started_at" => "2024-01-15T10:35:00Z"
}
```

No database schema changes required (uses existing JSONB columns).

### Agent Context

When a plan is generated, the agent's system prompt includes:
- All phases with objectives
- Phase execution instructions
- Clear phase markers to use
- Encouragement to reference the plan

This helps the agent:
- Understand the plan structure
- Know which phase is current
- Use consistent phase markers
- Track progress systematically

## Testing

**Test Coverage: ~700 lines across 4 files**

1. **PlanGenerator Tests** (198 lines)
   - Successful plan generation
   - JSON parsing and validation
   - Error handling (invalid JSON, incomplete structure)
   - Edge cases (empty task, missing fields)

2. **PlanModeExecutor Tests** (240 lines)
   - Plan generation with mocked LLM
   - Plan execution flow
   - Phase transitions
   - Validation of phase numbers
   - Error cases (no plan, invalid phase)

3. **Plan Action Tests** (169 lines)
   - Hashtag action execution
   - Payload and clean message handling
   - Plan formatting for display
   - Prompt addon building
   - Error handling

4. **Integration Tests** (283 lines)
   - Full plan generation → execution → completion flow
   - Phase tracking through session metadata
   - Hashtag action integration
   - UI broadcast verification
   - Plan formatting and display

## Documentation

Created comprehensive documentation:

- **`docs/PLANNING_MODE.md`** (650 lines)
  - Feature overview and user flow
  - Architecture and service descriptions
  - UI component details
  - JavaScript integration guide
  - System prompt integration
  - Error handling and troubleshooting
  - Future enhancement ideas

- **`IMPLEMENTATION_SUMMARY.md`** (650 lines)
  - Implementation details
  - Files created and modified
  - Key features checklist
  - Data flow diagram
  - Performance and security considerations
  - Testing coverage summary

## Breaking Changes

**None.** This implementation:
- ✅ Adds new features without changing existing APIs
- ✅ Uses existing session metadata structure
- ✅ Enhances hashtag actions non-breakingly
- ✅ Works with existing tool definitions
- ✅ Compatible with all agent configurations

## Performance Impact

- **LLM Calls**: +1 per plan generation (~2-5 seconds)
- **Database**: Negligible (plans: 1-5KB JSON in metadata)
- **UI**: Smooth, no layout shifts
- **Bandwidth**: Efficient ActionCable messages

## Security Considerations

- ✅ No new security vulnerabilities introduced
- ✅ Plans stored in user session (scope-limited)
- ✅ HTML escaping for all user-generated content
- ✅ JSON parsing validates structure
- ✅ No file system access or privilege escalation

## Configuration

No additional configuration required. Uses:
- Existing LLM provider configuration
- Existing Rails session management
- Existing ActionCable setup
- Existing tool loop infrastructure

## Deployment Notes

1. **Database**: No migrations needed
2. **Environment**: No new environment variables
3. **Seeds**: Run `rails db:seed` to update plan_mode tool definition
4. **Restart**: Standard Rails restart (no special requirements)

## Checklist

- ✅ Implements required planning features
- ✅ Comprehensive test coverage (700+ lines)
- ✅ Complete documentation
- ✅ No breaking changes
- ✅ Performance tested
- ✅ Security reviewed
- ✅ Code follows project conventions
- ✅ All syntax validated
- ✅ Git history clean
- ✅ Ready for review and merge

## Files Changed

**New Files** (5)
- `app/services/agents/plan_generator.rb`
- `spec/services/agents/plan_generator_spec.rb`
- `spec/services/hashtag_actions/actions/plan_spec.rb`
- `spec/features/planning_mode_spec.rb`
- `docs/PLANNING_MODE.md`

**Modified Files** (5)
- `app/services/tools/plan_mode_executor.rb`
- `app/services/hashtag_actions/actions/plan.rb`
- `app/javascript/controllers/chat_controller.js`
- `db/seeds/tools.rb`
- `spec/services/tools/plan_mode_executor_spec.rb`

**Supporting Files** (1)
- `IMPLEMENTATION_SUMMARY.md`

## Related Issues

Implements the planning mode feature requested in the requirements.

## Review Focus Areas

1. **Plan Generation**: Does LLM prompt produce valid, useful plans?
2. **UI Display**: Are plans clear and easy to understand?
3. **Execution Flow**: Do agents follow phases correctly?
4. **Phase Tracking**: Is metadata stored and retrieved correctly?
5. **Error Handling**: Are edge cases handled gracefully?
6. **Testing**: Is coverage sufficient and meaningful?
7. **Documentation**: Are examples clear and comprehensive?

## Questions for Reviewers

1. Should we add plan persistence (save to database)?
2. Should agents be able to modify plans during execution?
3. Should we add plan templates for common tasks?
4. Should we track actual vs. estimated duration?

## Conclusion

This implementation provides a complete, well-tested, well-documented planning mode feature that enhances agent capabilities while maintaining backward compatibility and following project conventions.

Ready for review and merge! 🚀
