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
