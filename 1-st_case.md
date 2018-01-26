### Исходный код
```
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
```

### Что не так:
1.Судя по возвращаемой ошибке, пользователь сначала получит сообщение, что ему нужно пройтись
  по всем данным, на которые ссылается 'client' и выкосить их вручную используя интерфейс.
  Избыточная и никому не нужная нагрузка. 
  А если у каждого клиента по 100000 ссылок по каждой связи и 100000 юзверей захотят их удалить?
  Правильно, все ляжет)

2. Метод в контроллере, высота которого перекрывает все на свете! (ребятам работающим в VIM ПРИВЕТ!:))

3. Метод если возвращает JSON, то он его должен в любом случае возвращать - хотя-бы пустой! 
В ином случае фронт обростает костылями.

### Решение:
1. Прописать в моделе Client по каждой НУЖНОЙ связи - 'dependent: :destroy',
Но при этом не забыть предупредить на фронте, при инициации удаления, что все связанные данные выкосятся автоматом.

```
class Client < ActiveRecord::Base
  has_many :agency_deals, dependent: :destroy
  has_many :agencies, dependent: :destroy
  ...
  # Здесь надо быть поосторожнее, чтобы при удалении не удалились другие клиенты, а только ссылки на них
  has_many :child_clients, dependent: :destroy
  ...
end
```

Но быстрее будет сделать 13 запросов к БД используя delete_all - иначе удаление зависимостей может затянуть с ответом:
Это валидно применять только тогда, когда каскад удаления не продолжается в объектах коллекции по ссылке дальше!
https://apidock.com/rails/ActiveRecord/Associations/CollectionProxy/delete_all

```
class Client < ActiveRecord::Base
  has_many :agency_deals, dependent: :delete_all
  has_many :agencies, dependent: :delete_all
  ...
  # Здесь надо быть поосторожнее, чтобы при удалении не удалились другие клиенты, а только ссылки на них
  has_many :child_clients, dependent: :delete_all
  ...
end
```

2. Решается путем решения '1.'

3. HTTP DELETE не должен возвращать данных, а только статус успех: 200,204,202 или лажа: 401,403,404... 

### Должно быть как-то так:
```
class Api::ClientsController < ApplicationController
  # Это можно прописать в классе родителе для JSON - ответов
  layout false 
  respond_to :json

  def destroy
    client&.destroy!
    render json: {}, head: :no_content
  end
end
```

PS: Не понятно, каким образом инстанс метод 'client' контроллера ищет клиента
```
class Api::ClientsController < ApplicationController
  def client 
    ??? 
  end
end
```
