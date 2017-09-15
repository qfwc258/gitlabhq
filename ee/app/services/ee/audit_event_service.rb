module EE
  module AuditEventService
    def for_member(member)
      action = @details[:action]
      old_access_level = @details[:old_access_level]
      author_name = @author.name
      user_id = member.id
      user_name = member.user ? member.user.name : 'Deleted User'

      @details =
        case action
        when :destroy
          {
            remove: "user_access",
            author_name: author_name,
            target_id: user_id,
            target_type: "User",
            target_details: user_name
          }
        when :create
          {
            add: "user_access",
            as: ::Gitlab::Access.options_with_owner.key(member.access_level.to_i),
            author_name: author_name,
            target_id: user_id,
            target_type: "User",
            target_details: user_name
          }
        when :update, :override
          {
            change: "access_level",
            from: old_access_level,
            to: member.human_access,
            author_name: author_name,
            target_id: user_id,
            target_type: "User",
            target_details: user_name
          }
        end

      self
    end

    def for_failed_login
      ip = @details[:ip_address]
      auth = @details[:with] || 'STANDARD'

      @details = {
        failed_login: auth.upcase,
        author_name: @author,
        target_details: @author,
        ip_address: ip
      }

      self
    end

    def for_changes
      @details =
        {
            change: @details[:as] || @details[:column],
            from: @details[:from],
            to: @details[:to],
            author_name: @author.name,
            target_id: @entity.id,
            target_type: @entity.class,
            target_details: @entity.name
        }
      self
    end

    def security_event
      if admin_audit_log_enabled?
        add_security_event_admin_details!

        return super
      end

      super if audit_events_enabled?
    end

    def add_security_event_admin_details!
      @details.merge!(ip_address: ip_address,
                      entity_path: @entity.full_path)
    end

    def audit_events_enabled?
      return true unless @entity.respond_to?(:feature_available?)

      @entity.feature_available?(:audit_events)
    end

    def admin_audit_log_enabled?
      License.feature_available?(:admin_audit_log)
    end

    def unauth_security_event
      return unless audit_events_enabled?


      @details.delete(:ip_address) unless admin_audit_log_enabled?
      @details[:entity_path] = @entity&.full_path

      SecurityEvent.create(
        author_id: @author&.id || -1,
        entity_id: @entity&.id || -1,
        entity_type: 'User',
        details: @details
      )
    end

    def method_missing(method_sym, *arguments, &block)
      super(method_sym, *arguments, &block) unless respond_to?(method_sym)

      for_custom_model(method_sym.to_s.split('for_').last, *arguments)
    end

    def respond_to?(method, include_private = false)
      method.to_s.start_with?('for_') || super
    end

    private

    def for_custom_model(model, key_title)
      action = @details[:action]
      model_class = model.camelize
      custom_message = @details[:custom_message]

      @details =
          case action
          when :destroy
            {
                remove: model,
                author_name: @author.name,
                target_id: key_title,
                target_type: model_class,
                target_details: key_title
            }
          when :create
            {
                add: model,
                author_name: @author.name,
                target_id: key_title,
                target_type: model_class,
                target_details: key_title
            }
          when :custom
            {
                custom_message: custom_message,
                author_name: @author&.name,
                target_id: key_title,
                target_type: model_class,
                target_details: key_title,
                ip_address: @details[:ip_address]
            }
          end

      self
    end

    def ip_address
      @author&.current_sign_in_ip || @details[:ip_address]
    end
  end
end
