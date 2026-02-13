# Test Coverage and Testing Strategy

> Steering document for maintaining high test coverage and quality standards.

---

## 1. Coverage Requirements

### Minimum Coverage Thresholds

- **Overall Coverage**: 95% minimum across the entire codebase
- **Diff Coverage**: 100% for any new or modified code
- **Line Coverage**: 95% minimum
- **Branch Coverage**: 90% minimum

### SimpleCov Configuration

SimpleCov should be configured to enforce these thresholds and fail the build if coverage drops below requirements.

```ruby
# spec/spec_helper.rb or spec/rails_helper.rb
require 'simplecov'

SimpleCov.start 'rails' do
  add_filter '/spec/'
  add_filter '/config/'
  add_filter '/vendor/'
  
  minimum_coverage 95
  minimum_coverage_by_file 80
  refuse_coverage_drop :maximum_coverage_drop, 2
  
  # Track branches for better coverage metrics
  enable_coverage :branch
end
```

---

## 2. Testing Scope

### What to Test

✅ **Models**
- Validations
- Associations
- Scopes
- Instance methods
- Class methods
- Callbacks
- Custom business logic

✅ **Controllers**
- HTTP request/response handling
- Parameter handling
- Authentication/authorization
- Redirects and renders
- Flash messages
- Session management
- Status codes

✅ **Services**
- Business logic
- Input validation
- Success and failure paths
- Error handling
- Return values (ServiceResponse)

✅ **Queries**
- Data retrieval logic
- Filtering and sorting
- Complex SQL queries
- Scopes and joins

✅ **Helpers**
- View helper methods
- Formatting logic
- Conditional rendering logic

✅ **Jobs**
- Background job execution
- Argument handling
- Error handling

✅ **Mailers**
- Email content
- Recipients
- Subject lines
- Attachments

---

### What NOT to Test

❌ **System/Feature Tests (Capybara)**
- No browser-based end-to-end tests
- No JavaScript interaction tests
- No full user flow tests through the UI

❌ **JavaScript Tests**
- No Stimulus controller tests
- No frontend JavaScript unit tests
- No integration tests for JS behavior

❌ **View Templates**
- No direct ERB template testing
- Test view logic through controller specs instead

❌ **Third-Party Libraries**
- Don't test Rails framework behavior
- Don't test gem functionality
- Only test your integration with them

---

## 3. Test Types and Priorities

### Primary Test Types (Required)

1. **Model Specs** (`spec/models/`)
   - Test all public methods
   - Test validations with valid and invalid data
   - Test associations
   - Test scopes and class methods
   - Test callbacks and their side effects

2. **Controller Specs** (`spec/controllers/`)
   - Test all controller actions
   - Test authentication and authorization
   - Test parameter handling and strong params
   - Test response codes and redirects
   - Test flash messages
   - Test session data manipulation

3. **Request Specs** (`spec/requests/`)
   - Use for integration testing across multiple controllers
   - Test API endpoints
   - Test complex workflows that span multiple requests
   - Test authentication flows

4. **Service Specs** (`spec/services/`)
   - Test all service objects
   - Test success and failure paths
   - Test error handling
   - Verify ServiceResponse structure

5. **Query Specs** (`spec/queries/`)
   - Test data retrieval logic
   - Test filtering and sorting
   - Verify correct records are returned

---

## 4. Testing Best Practices

### Controller Testing Strategy

Since we're not using Capybara, controller tests are critical for verifying the full request/response cycle.

```ruby
# spec/controllers/admin/delivery_zones_controller_spec.rb
RSpec.describe Admin::DeliveryZonesController, type: :controller do
  let(:admin_user) { create(:admin_user) }
  
  before { sign_in admin_user }
  
  describe "GET #index" do
    it "returns a successful response" do
      get :index
      expect(response).to be_successful
    end
    
    it "assigns all delivery zones" do
      zone1 = create(:delivery_zone)
      zone2 = create(:delivery_zone)
      get :index
      expect(assigns(:delivery_zones)).to match_array([zone1, zone2])
    end
  end
  
  describe "POST #create" do
    context "with valid parameters" do
      let(:valid_params) do
        { delivery_zone: { name: "Test Zone", area_wkt: "POLYGON((...))", active: true } }
      end
      
      it "creates a new delivery zone" do
        expect {
          post :create, params: valid_params
        }.to change(DeliveryZone, :count).by(1)
      end
      
      it "redirects to the index page" do
        post :create, params: valid_params
        expect(response).to redirect_to(admin_delivery_zones_path)
      end
      
      it "sets a success flash message" do
        post :create, params: valid_params
        expect(flash[:notice]).to be_present
      end
    end
    
    context "with invalid parameters" do
      let(:invalid_params) do
        { delivery_zone: { name: "", area_wkt: "" } }
      end
      
      it "does not create a new delivery zone" do
        expect {
          post :create, params: invalid_params
        }.not_to change(DeliveryZone, :count)
      end
      
      it "renders the new template" do
        post :create, params: invalid_params
        expect(response).to render_template(:new)
      end
      
      it "returns unprocessable entity status" do
        post :create, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
```

### Coverage Verification

Run tests with coverage reporting:

```bash
# Run all specs with coverage
bundle exec rspec

# View coverage report
open coverage/index.html

# Check coverage percentage
bundle exec rspec --format documentation
```

### Continuous Integration

Ensure CI pipeline fails if coverage drops below thresholds:

```yaml
# .github/workflows/test.yml or similar
- name: Run tests with coverage
  run: bundle exec rspec
  
- name: Check coverage
  run: |
    if [ $(grep -oP 'covered at \K[0-9.]+' coverage/.last_run.json | head -1) -lt 95 ]; then
      echo "Coverage below 95%"
      exit 1
    fi
```

---

## 5. Test Data Management

### FactoryBot Usage

- Use `build` for in-memory objects when persistence isn't needed
- Use `create` only when database persistence is required
- Define traits for common variations
- Keep factories minimal and focused

```ruby
# spec/factories/delivery_zones.rb
FactoryBot.define do
  factory :delivery_zone do
    name { Faker::Address.community }
    area { RGeo::Geographic.spherical_factory(srid: 4326).polygon(...) }
    active { true }
    
    trait :inactive do
      active { false }
    end
    
    trait :with_complex_boundary do
      area { RGeo::Geographic.spherical_factory(srid: 4326).polygon(...) }
    end
  end
end
```

---

## 6. Mocking and Stubbing

### When to Mock

✅ External API calls
✅ Time-dependent behavior
✅ File system operations
✅ Email delivery
✅ Background job enqueuing

### When NOT to Mock

❌ Database queries (use real DB in tests)
❌ ActiveRecord associations
❌ Model validations
❌ Service objects under test
❌ Internal application logic

```ruby
# Good: Stub external API
allow(Geocoder).to receive(:search).and_return([geocoded_result])

# Bad: Don't stub the class under test
# allow(DeliveryZone).to receive(:find_zone_for_point).and_return(zone)
```

---

## 7. Test Organization

### File Structure

```
spec/
├── controllers/
│   ├── admin/
│   │   ├── base_controller_spec.rb
│   │   └── delivery_zones_controller_spec.rb
│   └── address_verifications_controller_spec.rb
├── models/
│   ├── address_spec.rb
│   ├── admin_user_spec.rb
│   └── delivery_zone_spec.rb
├── services/
│   └── delivery_eligibility_service_spec.rb
├── queries/
│   └── [query_specs]
├── requests/
│   └── [integration_specs]
├── factories/
│   ├── addresses.rb
│   ├── admin_users.rb
│   └── delivery_zones.rb
├── support/
│   ├── database_cleaner.rb
│   └── devise.rb
├── rails_helper.rb
└── spec_helper.rb
```

---

## 8. Golden Rules

✅ Maintain 95% overall coverage, 100% diff coverage
✅ Test controllers, not views or JavaScript
✅ Use controller specs to verify full request/response cycle
✅ Test all public methods and business logic
✅ Use real database queries, not mocks
✅ Keep tests fast and focused
✅ One logical assertion per test when practical
✅ Test behavior, not implementation
✅ Use descriptive test names that explain intent

❌ No Capybara/system tests
❌ No JavaScript testing
❌ No view template testing
❌ No testing of third-party library internals
❌ No mocking internal application logic
❌ No property-based testing (PBT) - use standard unit tests only
