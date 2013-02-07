# Did I Pass for HSR

## Installation on Heroku
```
# Clone the repository
git clone https://github.com/mweibel/DidIPass.git && cd DidIPass

# Create a new app
heroku create
# Add addons
heroku addons:add scheduler:standard
heroku addons:add redistogo:nano
# Add configuration
heroku config:add NOTIFIER='Prowl' # Prowl notifier (currently the only available)
heroku config:add HSR_USERNAME='<your-hsr-username>'
heroku config:add HSR_PASSWORD='<your-hsr-password>'
heroku config:add PROWL_API_KEY='<prowl-api-key>'
heroku config:add CACHE='Redis'

# Push to heroku
git push heroku master

# Open the scheduler configuration and create a new task: 'ruby task.rb', every 3 hours
heroku addons:open scheduler

# Test if the task works...
heroku run ruby task.rb
```

## Installation somewhere else
```
# Clone the repository
git clone https://github.com/mweibel/DidIPass.git && cd DidIPass

# Install dependencies
bundle install

# Configuration (might be needed to prefix before the command in the cronjob config
export NOTIFIER='Prowl'
export HSR_USERNAME='<your-hsr-username>'
export HSR_PASSWORD='<your-hsr-password>'
export PROWL_API_KEY='<prowl-api-key>'
export CACHE='Redis' or export CACHE='File'
export CACHE_PATH='<path>' # if CACHE='FILE' && default path is not working for you (pwd of task.rb + /.cache)

# Edit crontab to add it
crontab -e

# Run it for testing
./task.rb
```

## License
DidIPassHSR is released under MIT License (see LICENSE).
