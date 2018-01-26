### Исходный код

```
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
```

### Что не так:

1. Любой файл или сложную операцию надо запускать в бэкграунд процессе - это правильно, 
 но реализацию логики этой обработки надо осуществлять или в моделе или в сервисе. Т.е. Логики процессинга файла в воркере не должно быть! Если сервис для контроллера - то он именуется c постфиксом 'Service' (e.g. ServiceNameService), если другой сервис, то с постфиксом 'Processor' (e.g. ServiceNameProcessor)
 Также запускать воркер на уровне контроллера не праильно, так как снначала надо проверить авлидность файла в моделе и в коллбэке after_save уже его запускать.

2. Ссылка на файл прилетает отдельно от параметров клиента - это не правильно, так как метод create должен отвечать только за создания клиента в данном контексте, а для процессинга файлов нужно создать новый контроллер или запихнуть параметр :file в параметры клиента и валидировать его на уровне модели, на ряду с другими параметрами относящимися к клиенту.

```
 params[:client] = {
  first_name: 'Billy',
  last_name: 'Jean',
  ...
  file: {
    s3_file_path: 'tralala',
    original_filename: 'someFileName.csv'
  }
 }
```


### Как можно сделать:

```
class Api::ClientsController < ApplicationController
  def create
    # NOTICE: Все ActiveRecord::Errors исключения я бы перехватывал и заворачивал в json ответ
    # чтобы не дублировать в каждом месте сообщение и код возврата ошибки
    render json: ClientService.create!(client_params)
  end
end  
```
