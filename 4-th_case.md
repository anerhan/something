### Исходный код

```
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
  ```

### Что не так:

1. Этот парсер не должен быть методом
2. Скорее всего это экпорт в CSV  Company.deals без входящих доп-фильтров, а это значит что можно процессору  передать ID Компании и всю логику реализовать в прцессоре со своими свойствами и аксессорами e.g.:

```
csv_data = CompanyDealsCsvProcessor.new(company_id: company.id).export
```

3. В том-же процессоре определить константу с полями хидера и т.д....
4. Дополнение хидерами 'company.deal_custom_field_names' 

### Решение:

Как и в предыдущих случаях - долго описывать и проще сделать) Но чтобы сделать надо быть в курсе контекста

### Как бы я сделал:

- Все хидер-поля перевел бы в labels, и каждому из label поставил бы в соответствие акссессор процессора.
- Перевод каждого из label спятал бы с помощью I18n.
 ```
 class CompanyDealsCsvProcessor < BaseProcessor
    BASE_HEADERS = %w[deal_id name advertiser ...].freeze
     
    def initialize(opts = {})
      @company = Company.find(opts[:company_id])
      return unless @company # NOTICE: или  raise
      @deals = @company.deals
      return unless @deals   # NOTICE: или  raise
    end  

    def export
      CSV.generate do |csv|
        csv << translated_headers
        @deals.each do |deal|
          csv << Deal.new(deal: deal, fields: headers).parse
        end
      end
    end

    private
    
    def headers
      @headers ||= BASE_HEADERS + @company.active_deal_labels
    end

    def translated_headers
      @translated_headers ||= headers.map {|h| I18n.t(h)}
    end

    class Deal
      def initialize(opts = {})
        @deal = opts[:deal]
        @fields = opts[:fields]      
      end

      def parse
        @fields.map {|f| self.try(:'#{f}')}
      end

      private
      # INFO: Аксессоры не являющиеся свойствами объекта Deal
      def stage_probability
        @deal.stage&.probability
      end
      ...
    end
 end
 ```

```
class Company
  scope :active_deal_fields, -> { self.where('disabled IS NOT TRUE').order('position asc').pluck(:field_label) }

  def active_deal_labels
    active_deal_fields.pluck(:field_label)
  end
  ...
end
```
