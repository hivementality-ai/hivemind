# RSpec Best Practices

> Steering document for consistent, maintainable, and meaningful tests.

---

## 1. Philosophy

RSpec tests should describe **what** the system does, not **how** it does it.  
They should verify behavior through public interfaces and avoid coupling to implementation details.

---

## 2. Test the Public Interface

- ✅ Only test **public methods** and **observable outcomes**.  
- ❌ Never test private methods directly. If you feel the need, extract that logic into a service or PORO.

Example:

```ruby
describe "#full_name" do
  it "concatenates first and last name" do
    user = build(:user, first_name: "John", last_name: "Doe")
    expect(user.full_name).to eq("John Doe")
  end
end
```

---

## 3. Structure: `describe`, `context`, `it`

Organize examples logically:

```ruby
describe Order do
  describe "#total_price" do
    context "with discounts" do
      it "applies the discount" do
        # ...
      end
    end

    context "without discounts" do
      it "returns the base price" do
        # ...
      end
    end
  end
end
```

---

## 4. Using `let` and `let!`

- `let` is **lazy** — runs when first called.
- `let!` is **eager** — runs before each example.
- Prefer `let` over instance variables for clarity.
- Avoid overusing many `let` blocks; prioritize readability.

Example:

```ruby
let(:user) { create(:user) }
let!(:order) { create(:order, user:) }
```

---

## 5. Shared Examples and Contexts

Use `shared_examples` for reusable, **behavioral** patterns — not just to DRY code.

```ruby
shared_examples "a soft deletable model" do
  it "marks the record as deleted" do
    subject.destroy
    expect(subject.deleted_at).not_to be_nil
  end
end

describe User do
  it_behaves_like "a soft deletable model"
end
```

---

## 6. FactoryBot Usage

- ✅ Use `build` for in-memory objects, `create` for persisted ones.  
- ✅ Define `traits` for state variation.  
- ✅ Keep factories simple — avoid deep association chains.  
- ❌ Don’t use factories in `before(:all)` (state leaks).

Example:

```ruby
factory :user do
  first_name { "John" }
  last_name  { "Doe" }

  trait :admin do
    role { :admin }
  end
end
```

---

## 7. Mocks and Stubs

- ✅ Stub external dependencies (API calls, email, etc.).
- ✅ Use `instance_double` to ensure method contracts.
- ❌ Avoid mocking or stubbing methods on the class under test.

---

## 8. Style Guidelines

- Use `expect(...).to` syntax (not `should`).
- Each example tests one logical behavior.
- Name `it` blocks descriptively (“returns 400 when params missing”).
- Run specs with random order (`--order random`).
- Keep test suite fast — reduce DB hits and over-factory usage.

---

## 9. Test Pyramid

- Unit: fastest, isolated logic.
- Integration: multiple components.
- Feature/System: full end-to-end user flows.

Aim for **many unit tests, fewer integration tests**, and only **essential system specs**.

---

## 10. Golden Rules

✅ Test intent, not implementation.
✅ One expectation per example when practical.
✅ Favor readability and explicit setup.
✅ Ensure every test describes behavior, not mechanics.

---

## 11. Testing Services (ServiceResponse)

Services return `ServiceResponse`, so tests follow a consistent shape: check `success?`, inspect `data` or `error`, and verify side effects.

### Basic Pattern

```ruby
# spec/services/vault/read_spec.rb
context "when entry exists" do
  let!(:vault_entry) { create(:vault_entry, namespace: "secrets", key: "api_key", encrypted_value: "secret123") }

  it "returns success with the value" do
    result = described_class.call(namespace: "secrets", key: "api_key")

    expect(result.success?).to be true
    expect(result.data[:value]).to eq("secret123")
  end
end

context "when entry does not exist" do
  it "returns failure with error message" do
    result = described_class.call(namespace: "secrets", key: "api_key")

    expect(result.success?).to be false
    expect(result.error).to eq("Secret not found: secrets/api_key")
  end
end
```

### Verifying Side Effects

Check that background jobs were enqueued, audit logs were created, etc.:

```ruby
it "creates an audit log entry" do
  expect {
    described_class.call(namespace: "secrets", key: "api_key")
  }.to change { Sidekiq::Job.jobs.size }.by(1)

  job = Sidekiq::Job.jobs.last
  expect(job["class"]).to eq("AuditLogJob")
end
```

### Rules

- ✅ Context split: `"when entry exists"` vs `"when entry does not exist"`.
- ✅ Always assert on `result.success?` before inspecting `data` or `error`.
- ✅ Test side effects (enqueued jobs, created records) separately from return values.

---

## 12. Testing Jobs

### Setup Pattern

Mock external dependencies in `before` — jobs typically interact with adapters, ActionCable, and other services:

```ruby
# spec/jobs/chat_stream_job_spec.rb
let(:adapter) { instance_double("Providers::AnthropicAdapter") }
let(:resolver_result) { double(success?: true, data: { adapter: adapter }) }

before do
  allow(ActionCable.server).to receive(:broadcast)
  allow(Providers::Resolver).to receive(:call).and_return(resolver_result)
end
```

### Testing Streaming Blocks

When the adapter yields chunks via a block, stub with a block that simulates streaming:

```ruby
before do
  allow(adapter).to receive(:chat) do |**_opts, &block|
    block.call(type: "content", content: "Hi there!")
    double(success?: true, data: { content: "Hi there!", usage: { input_tokens: 10, output_tokens: 5 } })
  end
end

it "streams response via ActionCable" do
  described_class.perform_now(session.id, "Hello")
  expect(ActionCable.server).to have_received(:broadcast)
    .with(channel, hash_including(type: "token", content: "Hi there!"))
end
```

### Test Multiple Paths

Cover bypass paths, normal flow, and error handling in separate contexts:

```ruby
context "hashtag bypass" do
  it "broadcasts response and returns without calling LLM" do
    described_class.perform_now(session.id, "#help")
    expect(Providers::Resolver).not_to have_received(:call)
  end
end

context "error handling" do
  before { allow(adapter).to receive(:chat).and_raise(StandardError, "LLM exploded") }

  it "broadcasts error on exception" do
    described_class.perform_now(session.id, "Hello")
    expect(ActionCable.server).to have_received(:broadcast)
      .with(channel, hash_including(type: "error"))
  end
end
```

---

## 13. WebMock & External APIs

### Global Setup

Disable all outbound HTTP in `rails_helper.rb`, allowing only localhost (for Capybara):

```ruby
# spec/rails_helper.rb
WebMock.disable_net_connect!(allow_localhost: true)
```

### Exact URL Stubs

Pin the URL, headers, and body for precision:

```ruby
stub_request(:post, "https://slack.com/api/chat.postMessage")
  .with(
    headers: { "Authorization" => "Bearer #{slack_token}" },
    body: hash_including("channel" => "C123456", "text" => "Hello Slack")
  )
  .to_return(status: 200, body: { ok: true, ts: "123" }.to_json)
```

### Regex URL Matching

For APIs where the query string varies, use a regex:

```ruby
stub_request(:get, /api.search.brave.com/)
  .to_return(status: 200, body: {
    web: { results: [{ title: "Ruby", url: "https://ruby-lang.org", description: "A language" }] }
  }.to_json)
```

### Asserting the Full Round-Trip

Stub the HTTP call, invoke the service, and verify both the parsed response and the `ServiceResponse`:

```ruby
it "parses Brave API response into results" do
  stub_request(:get, /api.search.brave.com/).to_return(status: 200, body: response_json)

  results = subject.search("ruby programming", count: 2)

  expect(results.size).to eq(2)
  expect(results.first).to be_a(Search::Base::Result)
  expect(results.first.title).to eq("Ruby Lang")
end
```

---

## 14. Test Infrastructure

Key conventions from `rails_helper.rb` that affect how specs run.

### DatabaseCleaner

`:transaction` by default (fast), `:truncation` for system specs (separate browser thread):

```ruby
config.before { DatabaseCleaner.strategy = :transaction }
config.before(:each, type: :system) { DatabaseCleaner.strategy = :truncation }

config.before { DatabaseCleaner.start }
config.after  { DatabaseCleaner.clean }
```

### Sidekiq

Fake mode by default — jobs are pushed to an in-memory array, not executed. Clear between examples:

```ruby
config.before do
  Sidekiq::Testing.fake!
end

config.after do
  Sidekiq::Job.clear_all
end
```

### Devise

Integration helpers are included by spec type:

```ruby
config.include Devise::Test::IntegrationHelpers, type: :request
config.include Devise::Test::IntegrationHelpers, type: :system
```

### SimpleCov

Branch coverage is enabled with minimum thresholds:

```ruby
SimpleCov.start "rails" do
  enable_coverage :branch
  minimum_coverage 30
  minimum_coverage_by_file 0
  minimum_coverage branch: 10
end
```

---

## 15. Shoulda Matchers + Custom Validations

### Standard Validations with Shoulda

Use one-liners for associations and simple validations:

```ruby
describe "associations" do
  it { should belong_to(:agent) }
  it { should belong_to(:source).optional }
end

describe "validations" do
  it { should validate_presence_of(:content) }
end
```

### Custom Validations with Explicit Specs

For enums, conditional validations, and complex rules, write explicit examples:

```ruby
it "validates memory_type inclusion" do
  entry = build(:memory_entry, memory_type: "invalid")
  expect(entry).not_to be_valid
end

it "allows valid memory types" do
  %w[episodic semantic procedural preference].each do |type|
    entry = build(:memory_entry, memory_type: type)
    expect(entry).to be_valid
  end
end
```

### Rules

- ✅ Use Shoulda for `validates_presence_of`, `belongs_to`, `has_many`, etc.
- ✅ Use explicit specs for enum inclusion, conditional validations, and business rules.
- ❌ Don't force Shoulda matchers for validations it doesn't support well — readability wins.
