# Rails Best Practices

> Steering document for writing clean, scalable, maintainable Rails code.

---

## 1. Core Philosophy

- **Skinny Controllers, Fat Models** — but avoid obese models.  
- **Single Responsibility Principle (SRP):** each class or module should do one thing well.  
- **Explicit over implicit:** always favor readability and clarity.

---

## 2. Controllers

Controllers should handle **HTTP orchestration only**:
- Parsing params
- Authorizing access
- Calling services/queries
- Rendering results or errors

Example:

```ruby
class OrdersController < ApplicationController
  def create
    response = Orders::Create.call(order_params:, user: current_user)

    if response.success?
      render json: response.data[:order], status: :created
    else
      render json: { errors: response.error }, status: :unprocessable_entity
    end
  end

  private

  def order_params
    params.require(:order).permit(:product_id, :quantity)
  end
end
```

---

## 3. Service Objects

### Philosophy

Service objects encapsulate a **single unit of business logic**.  
They should use **keyword arguments only**, and return a standardized **`ServiceResponse`**.

---

### The `ServiceResponse` Class

```ruby
# app/lib/service_response.rb
class ServiceResponse
  attr_reader :success, :data, :error
  alias_method :success?, :success

  def initialize(success:, data: nil, error: nil)
    @success = success
    @data = data
    @error = error
  end

  def self.success(data: nil)
    new(success: true, data:)
  end

  def self.failure(error:)
    new(success: false, error:)
  end
end
```

---

### Example: Orders::Create Service

```ruby
# app/services/orders/create.rb
module Orders
  class Create
    def self.call(order_params:, user:)
      new(order_params:, user:).call
    end

    def initialize(order_params:, user:)
      @order_params = order_params
      @user = user
    end

    def call
      order = Order.new(@order_params.merge(user: @user))

      if order.save
        ServiceResponse.success(data: { order: })
      else
        ServiceResponse.failure(error: order.errors.full_messages)
      end
    end
  end
end
```

---

### Rules

- ✅ Keyword args only (`def call(order_params:, user:)`).
- ✅ Always return a `ServiceResponse`.
- ✅ Stateless and idempotent — no persistent side effects.
- ❌ No positional args.
- ❌ No direct rendering or persistence in controller logic.

---

## 4. Query Objects

Extract reusable data retrieval patterns.

```ruby
# app/queries/orders/recent_for_user.rb
module Orders
  class RecentForUser
    def self.call(user:)
      Order.where(user:).where("created_at > ?", 30.days.ago)
    end
  end
end
```

Use queries for:
- Complex or reusable ActiveRecord scopes.
- Filtering or sorting logic.

---

## 5. Models

Models define:
- Associations
- Validations
- Simple domain logic

Avoid stuffing models with orchestration or data-fetching logic.

Example:

```ruby
class Order < ApplicationRecord
  belongs_to :user
  has_many :line_items

  validates :total, numericality: { greater_than: 0 }

  scope :recent, -> { where("created_at > ?", 30.days.ago) }
end
```

---

## 6. Concerns and Modules

- ✅ Use concerns for **shared domain behavior** (e.g. `Searchable`, `Archivable`).
- ❌ Don’t hide complexity by dumping large chunks of logic in them.
- Each concern should define a clear, single responsibility.

---

## 7. Error Handling

Centralize exception handling at the application layer.

```ruby
class ApplicationController < ActionController::Base
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "Not Found" }, status: :not_found
  end
end
```

Services should return `ServiceResponse.failure` with descriptive messages.

---

## 8. Testing Rails Architecture

- **Controllers:** routing, params, and response codes.  
- **Models:** validations and domain behavior.  
- **Services:** input/output contract.  
- **Queries:** correct dataset returned.

Don’t test internal implementation of Rails itself.

---

## 9. Code Organization

- Keep `app/services`, `app/queries`, and `app/lib` structured by domain.  
- Use consistent naming (`Users::Create`, `Payments::Refund`, etc.).  
- Always prefer **explicit dependency injection** (via keyword args) to globals.

---

## 10. Golden Rules

✅ Keyword args only in Service/Query objects.  
✅ Always return a `ServiceResponse`.  
✅ Controllers orchestrate, don’t compute.  
✅ Models validate, not coordinate.  
✅ Consistency > Cleverness.
