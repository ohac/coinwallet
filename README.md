    $ touch views/header.haml
    $ touch views/footer.haml
    $ cd public/js
    $ curl -sO http://code.jquery.com/jquery-2.1.4.min.js
    $ cd -
    $ cp config.example.yml config.yml
    $ vi config.yml
    $ cp config.example.ru config.ru
    $ vi config.ru
    $ bundle install
    $ bundle exec rackup

    visit: http://localhost:4568/
    login as: foo foo@example.com
