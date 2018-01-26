# 2 =================================================================================
class Api::ClientsController < ApplicationController
  def destroy
    errors = []
    if client.agency_deals.count > 0 || client.advertiser_deals.count > 0
      errors << 'Deal'
    end
    if client.agency_activities.count > 0 || client.activities.count > 0
      errors << 'Activity'
    end
    if client.contacts.count > 0 || client.primary_contacts.count > 0 || client.secondary_contacts.count > 0
      errors << 'Contact'
    end
    if client.agency_ios.count > 0 || client.advertiser_ios.count > 0
      errors << 'IO'
    end
    if client.bp_estimates.count > 0
      errors << 'Business Plan'
    end
    if client.child_clients.count > 0
      errors << 'Account'
    end
    if client.advertisers.count > 0
      errors << 'Agency'
    end
    if client.agencies.count > 0
      errors << 'Advertiser'
    end

    if errors.count > 0
      render json: { error: "This account is used on #{errors.join(', ')}. Remove all references to this record before deleting." }, status: :unprocessable_entity
    else
      client.destroy
      render nothing: true
    end
  end
end



# 2 =================================================================================
class Api::ClientsController < ApplicationController
  def index
    respond_to do |format|
      format.json {
        if params[:name].present?
           results = suggest_clients
        else
          results = clients
                      .by_type_id(params[:client_type_id])
                      .by_category(params[:client_category_id])
                      .by_region(params[:client_region_id])
                      .by_segment(params[:client_segment_id])
                      .by_city(params[:city])
                      .by_last_touch(params[:start_date], params[:end_date])
                      .by_name(params[:search])
                      .order(:name)
                      .preload(:address, :client_member_info, :latest_advertiser_activity, :latest_agency_activity)
                      .distinct
        end

        if params[:owner_id]
          client_ids = Client.joins("INNER JOIN client_members ON clients.id = client_members.client_id").where("clients.company_id = ? AND client_members.user_id = ?", company.id, params[:owner_id]).pluck(:client_id)
          results = results.by_ids(client_ids)
        end

        response.headers['X-Total-Count'] = results.count.to_s
        results = results.limit(limit).offset(offset)
        render json: results,
          each_serializer: Clients::ClientListSerializer,
            advertiser: Client.advertiser_type_id(company),
            agency: Client.agency_type_id(company),
            categories: category_options
      }
    end
  end
end



# 3 =================================================================================

class Api::ClientsController < ApplicationController
  def create
    if params[:file].present?
      CsvImportWorker.perform_async(
        params[:file][:s3_file_path],
        'Client',
        current_user.id,
        params[:file][:original_filename]
      )

      render json: { message: "Your file is being processed. Please check status at Import Status tab in a few minutes (depending on the file size)" }, status: :ok
    else
      client = company.clients.new(client_params)
      client.created_by = current_user.id

      if client.save
        render json: client, status: :created
      else
        render json: { errors: client.errors.messages }, status: :unprocessable_entity
      end
    end
  end
end



# 4 =================================================================================
def self.to_csv(deals, company)
    CSV.generate do |csv|
      header = ['Deal ID', 'Name', 'Advertiser',
                'Agency', 'Team Member', 'Budget',
                'Currency', 'Stage', 'Probability',
                'Type', 'Source', 'Next Steps',
                'Start Date', 'End Date', 'Created Date',
                'Closed Date', 'Close Reason', 'Budget USD', 'Created By']

      deal_custom_field_names = company.deal_custom_field_names.where("disabled IS NOT TRUE").order("position asc")
      deal_custom_field_names.each do |deal_custom_field_name|
        header << deal_custom_field_name.field_label
      end

      deal_settings_fields = company.fields.where(subject_type: 'Deal').pluck(:id, :name)

      csv << header
      deals.find_each do |deal|
        agency_name = deal.agency.try(:name)
        advertiser_name = deal.advertiser.try(:name)
        stage_name = deal.stage.try(:name)
        stage_probability = deal.stage.try(:probability)
        budget_loc = (deal.budget_loc.try(:round) || 0)
        budget_usd = (deal.budget.try(:round) || 0)

        member = deal.deal_members.collect {|deal_member| deal_member.email + "/" + deal_member.share.to_s}.join(";")
        line = [
          deal.id,
          deal.name,
          advertiser_name,
          agency_name,
          member,
          budget_loc,
          deal.curr_cd,
          stage_name,
          stage_probability,
          deal.get_option_value_from_raw_fields(deal_settings_fields, 'Deal Type'),
          deal.get_option_value_from_raw_fields(deal_settings_fields, 'Deal Source'),
          deal.next_steps,
          deal.start_date,
          deal.end_date,
          deal.created_at.strftime("%Y-%m-%d"),
          deal.closed_at,
          deal.get_option_value_from_raw_fields(deal_settings_fields, 'Close Reason'),
          budget_usd,
          deal.creator.email
        ]

        csv << line
      end
    end
  end




# 5 =================================================================================
def self.import(file)
  CSV.parse(file, headers: true, header_converters: :symbol) do |row|
    import_log.count_processed

    if row[0]
      begin
        deal = current_user.company.deals.find(row[0].strip)
      rescue ActiveRecord::RecordNotFound
        import_log.count_failed
        import_log.log_error(["Deal ID #{row[0]} could not be found"])
        next
      end
    end

    if row[1].nil? || row[1].blank?
      import_log.count_failed
      import_log.log_error(["Deal name can't be blank"])
      next
    end

    if row[2].present?
      advertiser_type_id = Client.advertiser_type_id(current_user.company)
      advertisers = current_user.company.clients.by_type_id(advertiser_type_id).where('name ilike ?', row[2].strip)
      if advertisers.length > 1
        import_log.count_failed
        import_log.log_error(["Advertiser #{row[2]} matched more than one account record"])
        next
      elsif advertisers.length == 0
        import_log.count_failed
        import_log.log_error(["Advertiser #{row[2]} could not be found"])
        next
      else
        advertiser = advertisers.first
      end
    else
      import_log.count_failed
      import_log.log_error(["Advertiser can't be blank"])
      next
    end
  end
