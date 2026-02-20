# Planning Mode Implementation Summary

## Overview

This implementation adds Claude Code-style planning mode to Hivemind agents. Users can now:
1. Generate detailed work plans by using the `#plan` hashtag
2. View plans as structured, expandable cards in the chat UI
3. Watch agents execute plans phase-by-phase with clear progress tracking

## Files Created

### Services

1. **`app/services/agents/plan_generator.rb`** (NEW - 122 lines)
   - Generates structured work plans via LLM
   - Validates plan structure (overview, context, phases, success criteria)
   - Returns ServiceResponse with parsed plan or error
   - Key method: `call(agent:, task:, session:)`

### Tests

2. **`spec/services/agents/plan_generator_spec.rb`** (NEW - 198 lines)
   - Tests successful plan generation
   - Tests plan parsing and validation
   - Tests error handling (invalid JSON, incomplete structure, LLM failures)
   - 8 test contexts covering happy path and edge cases

3. **`spec/services/hashtag_actions/actions/plan_spec.rb`** (NEW - 169 lines)
   - Tests Plan hashtag action execution
   - Tests payload and clean_message handling
   - Tests plan formatting and display
   - Tests phase context building
   - 15 test cases

4. **`spec/features/planning_mode_spec.rb`** (NEW - 283 lines)
   - Integration tests for full planning workflow
   - Tests plan generation → execution → phase transitions
   - Tests hashtag action integration
   - Tests phase tracking in session metadata
   - 18 feature tests

### Documentation

5. **`docs/PLANNING_MODE.md`** (NEW - 650 lines)
   - Complete feature documentation
   - User flow and architecture
   - Service descriptions and API contracts
   - UI component details
   - System prompt integration
   - Error handling and troubleshooting guide
   - Testing strategy and future enhancements

## Files Modified

### Core Services

1. **`app/services/tools/plan_mode_executor.rb`** (ENHANCED)
   - Changed from enter/exit planning mode to: generate/execute/update_phase
   - Added plan generation with LLM via PlanGenerator
   - Added plan storage in session metadata
   - Added phase tracking and validation
   - Added ActionCable broadcasts for UI updates
   - Old: 56 lines → New: 120 lines

2. **`app/services/hashtag_actions/actions/plan.rb`** (ENHANCED)
   - Changed from simple planning mode trigger to full plan generation flow
   - Extracts task from payload or clean message
   - Calls plan_mode tool with generate action
   - Formats plan for display
   - Builds phase context for system prompt
   - Provides structured response to LLM
   - Old: 35 lines → New: 108 lines

### UI Layer

3. **`app/javascript/controllers/chat_controller.js`** (ENHANCED)
   - Added handlePlanMessage() method for plan message processing
   - Added displayPlan() to render plan cards with collapsible details
   - Added togglePlanDetails() for expand/collapse functionality
   - Added displayPlanExecution() for execution start indicator
   - Added updatePhaseDisplay() for phase transition messages
   - Added plan case to handleMessage() message dispatcher
   - Added helper method for HTML escaping

### Configuration

4. **`db/seeds/tools.rb`** (UPDATED)
   - Updated plan_mode tool definition to support new actions: generate/execute/update_phase
   - Enhanced description to reflect new capabilities
   - Added task parameter for plan generation
   - Added phase_number parameter for phase transitions

5. **`spec/services/tools/plan_mode_executor_spec.rb`** (REFACTORED)
   - Replaced enter/exit tests with generate/execute/update_phase tests
   - Added plan generation test with mocked LLM response
   - Added phase transition tests
   - Added validation tests for phase numbers
   - Old: 108 lines → New: 240 lines

## Key Features Implemented

### 1. Plan Generation
- ✅ LLM generates structured plans via PlanGenerator service
- ✅ Plans have 3-5 sequential phases
- ✅ Each phase includes: number, name, objectives, approach, tools, expected output
- ✅ Plans include: overview, context, success criteria, estimated duration
- ✅ JSON parsing with validation

### 2. Plan Display UI
- ✅ Collapsible card in chat showing overview and phases
- ✅ "Show Details" button to expand/collapse phase details
- ✅ Formatted phase list with phase numbers and names
- ✅ Detailed view showing objectives, approach, tools for each phase
- ✅ Success criteria and duration displayed

### 3. Plan Execution
- ✅ Agent receives phase context in system prompt
- ✅ Agent marks phase transitions with "## Phase N: [name]"
- ✅ Progress indicators show current phase / total phases
- ✅ Phase numbers track which phase agent is on

### 4. Phase Tracking
- ✅ Current phase stored in session.metadata["current_phase"]
- ✅ Current plan stored in session.metadata["current_plan"]
- ✅ Plan status: "generated" → "executing"
- ✅ Timestamps for plan generation and start
- ✅ Agent has full context for execution decisions

### 5. ActionCable Integration
- ✅ Plan broadcast on generation (type: "plan", action: "display")
- ✅ Execution start broadcast (action: "start_execution")
- ✅ Phase transition broadcast (action: "phase_update")
- ✅ Real-time UI updates via WebSocket

## Data Flow Diagram

```
User: #plan Build authentication
       ↓
Plan Hashtag Action (executed)
       ↓
Calls Tools::PlanModeExecutor (action: "generate", task: "...")
       ↓
Calls Agents::PlanGenerator
       ↓
Calls LLM (planning system prompt)
       ↓
LLM returns JSON plan
       ↓
Parse and validate plan
       ↓
Store in session.metadata["current_plan"]
       ↓
Broadcast via ActionCable (type: "plan", action: "display")
       ↓
JavaScript renders plan card with phases
       ↓
Agent's system prompt updated with phase context
       ↓
Agent begins execution: "## Phase 1: [name]"
       ↓
Agent executes objectives, reports progress
       ↓
Agent ready for next phase
       ↓
[Continue until all phases complete]
```

## Testing Coverage

- ✅ **PlanGenerator**: 8 test contexts covering plan generation, parsing, validation, error handling
- ✅ **PlanModeExecutor**: 10 test contexts covering generate/execute/update_phase actions
- ✅ **Plan Hashtag Action**: 15 test cases covering payload handling, formatting, prompt addon
- ✅ **Integration Tests**: 18 feature tests for full workflow
- ✅ **Total**: ~700 lines of tests across 4 files

## System Prompt Integration

When plan is generated, agent receives:

```
User has created a multi-phase plan:
Phase 1 (Database Setup): Create user table; Add password hashing
Phase 2 (Auth Routes): Create signup endpoint; Create login endpoint
Phase 3 (Session Management): Implement session storage; Add logout functionality

You will execute this plan phase by phase:
1. Start each phase with a clear marker: "## Phase N: [name]"
2. Execute the objectives for the current phase
3. Track your progress and show what you've accomplished
4. When ready, move to the next phase

You can reference the plan whenever needed to stay on track.
```

## Example Usage

### User initiates plan:
```
User: #plan Build a REST API with JWT authentication and database models
```

### Agent responds with plan:
```
✅ Plan generated! I'll now execute it phase by phase.

📋 **Plan Overview**: Implement a complete REST API with authentication

**Context**: Building a scalable API with JWT tokens and PostgreSQL database

**Phases**:

**Phase 1: Database Setup**
  - Objectives: Create database schema; Create models
  - Approach: Write migrations and ActiveRecord models
  - Tools needed: shell, file_write
  - Expected output: Database tables and models configured

[2 more phases...]

**Success Criteria**: API endpoints work; Authentication works; Data persists
**Estimated Duration**: 4-5 hours
```

### Agent executes plan:
```
## Phase 1: Database Setup
I'll start by creating the database schema and models...

[Agent creates migrations, models, runs migrations]

Phase 1 complete. Database schema is set up with user authentication.

## Phase 2: API Endpoints
Now I'll implement the REST API endpoints...

[Agent implements endpoints]

Phase 2 complete. All API endpoints are working.

## Phase 3: Authentication
Finally, I'll secure the API with JWT authentication...

[Agent implements JWT authentication]

All phases complete! Your API is ready for use.
```

## Migration Path

No database migrations required. Plans are stored in:
- `session.metadata` (existing JSONB column)
- No schema changes needed

## Backward Compatibility

- ✅ No breaking changes to existing APIs
- ✅ Existing hashtag actions unaffected
- ✅ Existing sessions continue to work
- ✅ Tool definitions updated non-breakingly

## Performance Considerations

- **LLM Calls**: One per plan generation (adds ~2-5 seconds)
- **Database**: Small metadata storage (JSON size: 1-5KB per plan)
- **Broadcasting**: Efficient ActionCable messages (plan + phase data)
- **UI**: No layout shifts, smooth expansion/collapse

## Security Considerations

- ✅ No sensitive data in plans
- ✅ Plans stored in session (user-scoped)
- ✅ No file system access
- ✅ LLM input properly escaped in HTML
- ✅ JSON parsing validates structure

## Future Enhancements

1. **Plan Persistence**: Save plans to database for retrieval
2. **Plan Templates**: Pre-built templates for common tasks
3. **Plan Variations**: Generate multiple approaches
4. **Plan Modifications**: Agent can update plan during execution
5. **Plan Metrics**: Track actual vs. estimated duration
6. **Collaborative Planning**: Multiple agents contribute
7. **Plan Visualization**: Gantt charts, timeline views

## Files Summary

```
New Files (5):
- app/services/agents/plan_generator.rb (122 lines)
- spec/services/agents/plan_generator_spec.rb (198 lines)
- spec/services/hashtag_actions/actions/plan_spec.rb (169 lines)
- spec/features/planning_mode_spec.rb (283 lines)
- docs/PLANNING_MODE.md (650 lines)

Modified Files (5):
- app/services/tools/plan_mode_executor.rb (enhanced: 56 → 120 lines)
- app/services/hashtag_actions/actions/plan.rb (enhanced: 35 → 108 lines)
- app/javascript/controllers/chat_controller.js (added plan handlers)
- db/seeds/tools.rb (updated plan_mode tool definition)
- spec/services/tools/plan_mode_executor_spec.rb (refactored: 108 → 240 lines)

Total New Code: ~1,600 lines
Total Test Code: ~700 lines
Total Documentation: ~650 lines
```

## Checklist

- ✅ Service layer implemented (PlanGenerator)
- ✅ Tool executor enhanced (PlanModeExecutor)
- ✅ Hashtag action updated (Plan)
- ✅ JavaScript handlers added (chat_controller)
- ✅ UI components rendered (plan cards)
- ✅ Session metadata tracking
- ✅ Phase context in system prompt
- ✅ ActionCable broadcasting
- ✅ Error handling implemented
- ✅ Comprehensive tests written
- ✅ Documentation completed
- ✅ Tool definition updated

## Ready for PR

This implementation is complete and ready for review. All components work together to provide:

1. **Plan Generation**: LLM creates structured, validated plans
2. **Plan Display**: Beautiful, interactive UI cards
3. **Plan Execution**: Agent executes phase-by-phase with context
4. **Progress Tracking**: Clear indicators of current phase and progress
5. **Error Handling**: Graceful failure with meaningful errors
6. **Testing**: Comprehensive test coverage
7. **Documentation**: Complete feature documentation

The implementation follows Hivemind conventions, uses existing patterns (ServiceResponse, tool loop, ActionCable), and integrates seamlessly with the agent system.
