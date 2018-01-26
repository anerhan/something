### Исходный код

```
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
```

### Что не так:

1. Этот парсер не должен быть методом
2. Скорее всего это импорт из CSV  Company.deals без входящих доп-фильтров, а это значит что можно процессору  передать ID Пользователя и файл, а всю логику реализовать в процессоре со своими свойствами и аксессорами e.g.:

```
csv_data = UserCompanyDealsCsvLoggerProcessor.new(user_id: current_user.id, file: file).import!
```

3. В том-же процессоре определить константу с полями хидера и т.д....
4. Поскольку в БД метод ничего не заносит, а просто выводит в лог статусы процесса парсинга - функционально метод бесполезен.  Такое впечасление что это дебаг в процессе разработки)

### Решение:

 Аналогичное 4-му кейсу, только реверс, а во снутреннем класе Deal реализовать сеттеры вместо аксессоров, для парсинга полей не входящих в массив labels для Header - ов
 ```
 class UserCompanyDealsCsvLoggerProcessor < BaseProcessor
  ...
  
  private

  class Deal
    # INFO: Сетторы не являющиеся сетторами AR объекта Deal
    def stage_probability=(stage_probability)
       # TODO: Распарсить параметр и преобразовать (установить) в свойства AR объекта для записи в БД
       ...
    end
    ...
  end
 end
 ```

### Как бы я сделал:

 ```
 class UserCompanyDealsCsvLoggerProcessor < BaseProcessor
  # INFO:  Все что нужно знать этому процессору - это user_id

  def import!
    # TODO: 
    # - По какому-то header-у выбрать поля, которые есть в свойствах объекта 
    # который нужно создать.  
    # - Забрать по позициям этих полей из каждой следующей строки значения
    # - Объект проверить на валидность deal.valid?
    # - Если валидный, то закинуть его в БД или коллекцию валидных бъектов
    # - Если не валидный, закинуть в какой-то общий для процесора контейнер
    # с номером строки и ошибкой для сохранения или вывода в лог...
  end
  ...
 end
 ```
