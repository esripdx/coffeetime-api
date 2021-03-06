CoffeeTime API
==============

## Authentication

* Create a sign-in button in the app, which launches a native browser to https://api.coffeetime.io/1/auth
* The user will be prompted with the Github OAuth screen
* When the user signs in, they will eventually be redirected back to coffeetime://auth?code=xxx
* The native app will launch, and you will need to parse the code out of the URL that launched the app
* Then make a POST request with the code: <pre>https://api.coffeetime.io/1/auth
code=xxx</pre>
* The response will contain an access token and user info which you can store on the device.

## API Docs

See [coffeetime.io/api](http://coffeetime.io/api/) for full API docs.
