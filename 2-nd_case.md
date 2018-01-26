### Исходный код
```
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
```

### Что не так:
1. Громоздкость
2. Отсутствие ограничения по параметрам params.permit(:limit, :offset, :client_type_id ...)
3. Возможно отсутствие дефолтных Limit - ов: Если Client.count > 100000 - то бэк присядет плотно вместе с БД и.т.д...)
4. response.headers['X-Total-Count'] - HardCode
5. Все сложные манипуляции c параметрами перенести в сервис, например ClientService
6. Логики формирования запросов к БД не должно быть в контроллере
5. Все аттрибуты параметров фильтрации децентрализованы (Нужно оперировать каждым по отдельности или таскать весь params).
6. Сериалайзер ActiveModel::Serializer имеет встроенный реляционный механизм
7. Distinct - не имеет смысла без указания поля или поля с другими полями и группировкой
8. Тофтология в названии сериалайзера Clients::ClientListSerializer => Client::ListSerializer

### Решение:
Здесь писать и писать...)



### Должно быть как-то так в итоге:
```
class Api::ClientsController < ApplicationController
  def index
    clients = ClientService.search(filter_attrs).limit(limit).offset(offset)
    set_count_response_header clients.count
    render json: clients, each_serializer: Clients::ClientListSerializer
  end

  private

  def filter_attrs
    params.require(:q).permit(:name_eq, :owner_id, :company_id, :client_type_id_eq, :client_category_id_eq...)
  end
end
```


**Сервис:**
Ransack: https://github.com/activerecord-hackery/ransack
```
class ClientService
  def initialize(opts = {})
  end

  class << self
    def search(q = {})
      Какая-то  доп. обработка параметров если надо...
      Client.ransack(q).ownered_by_company(q.delete(:owner_id), q.delete(:company_id))
    end
  end

end
```

**Модель:**
```
class Client < ActiveRecord::Base
 has_many :client_members
 scope :ownered_by_company, ->(owner_id, company_id) do
    if owner_id && company_id
      # INFO: joins по умолчанию использует пересечение => INNER JOIN...
      self.joins(:client_members).
        where('client_members.user_id = ? AND  client_members.company_id = ?', owner_id, company_id)
    end
 end 

 def company_advertizer(company_id)
   return unless company_id
   Advertizer.find_by(company_id: company_id)
 end

 def company_agency(agency_id)
   return unless company_id
   Advertizer.find_by(company_id: company_id)
 end

 def categories
    Какие-то категории, которые можно достать из контроллера и вставить в ссылку
 end

end
```

**Сериалайзер:**
```
class Client::ListSerializer < ActiveModel::Serializer
  attributes ..., :company_advertizer, :company_agency, :categories

  has_one: company_advertizer, serializer: Advertizer::Serializer
  has_one: company_agency, serializer: Agency::Serializer
  has_many: categories, serializer: Category::Serializer
  ...
end
```
