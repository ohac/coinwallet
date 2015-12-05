    $ touch views/header.haml
    $ touch views/footer.haml
    $ touch views/header.slim
    $ touch views/footer.slim
    $ cd public/js
    $ curl -sO http://code.jquery.com/jquery-2.1.4.min.js
    $ curl -sO http://code.jquery.com/jquery-2.1.4.min.js
    $ curl -sO https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/js/bootstrap.min.js
    $ cd -
    $ cd public/css
    $ curl -sO https://maxcdn.bootstrapcdn.com/bootstrap/3.3.6/css/bootstrap.min.css
    $ cd -
    $ cp config.example.yml config.yml
    $ vi config.yml
    $ cp config.example.ru config.ru
    $ vi config.ru
    $ bundle install
    $ bundle exec rackup

    visit: http://localhost:4568/
    login as: foo foo@example.com
