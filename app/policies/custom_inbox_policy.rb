class CustomInboxPolicy < ApplicationPolicy
  def create?
    @account_user.administrator?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def update?
    @account_user.administrator?
  end

  def destroy?
    @account_user.administrator?
  end

  def add_conversation_to_custom_inbox?
    @account_user.administrator? || @account_user.agent?
  end
end
