title: How I Run Hablog (Or Any Other Haskell Application) on Heroku with CircleCI
authors: Matt
route: hablog-on-heroku
date: 2014-11-08
tags: programming, haskell, hablog, heroku, circleci

---

# What is Hablog?

Hablog is a simple piece of Haskell code to serve a blog from flat files. It doesn't need a database or a
billion assets, and it's written in a language I'm trying to learn, so I figured it'd be a great tool to set
up on my new Heroku instance.

Unfortunately, I got stuck at the first hurdle: "How do I run the thing?"

Running Haskell on [Heroku](https://www.heroku.com) isn't as simple as running Node or Ruby, but it's not a
lost cause either. These instructions should be able to be modified for any Haskell code you want to run, but
I've only tested them with Hablog so far.

# What You Need

I'm going to assume you have three things for this post: a [Heroku](https://www.heroku.com) account, a 
[CircleCI](https://www.circleci.com) account, and a [GitHub](https://www.github.com) account. You'll also want
to fork [Hablog](https://github.com/soupi/hablog/) so that you can make the necessary changes. I'm going to
assume you have the application cloned locally.

# Let's Set Up Heroku

## Setting Up The Application

Go to your Heroku dashboard and create a new application. The name doesn't matter, but you'll need it for the
later stages, so make it something you'll remember. Once you've got this set up, you'll be presented with a
dashboard.

### The Null Buildpack

Navigate to the `Deploy` tab and make sure you have `Heroku Git` as your Deployment Method, then go
to `Settings` and scroll to Buildpacks, you'll want to add Ryan Smith's 
[Null Buildpack](https://github.com/ryandotsmith/null-buildpack), so click Add Buildpack
and enter this URL: `http://github.com/ryandotsmith/null-buildpack.git`.

![](https://imgur.com/mnC2zEW.png)

Buildpacks are a way to tell Heroku how to build and release the application. Since we'll be handling our build
process on CircleCI, we don't need Heroku to do anything except run the command, which is specified in the
`Procfile` in the root directory of the repository. 

## Procfile

We use the `Procfile` to tell Heroku how to run our application. This is 
[my Procfile](https://github.com/m-doughty/hablog/blob/master/Procfile), it's just `web:` (which tells Heroku
that this is a Web application and needs to bind to an external port) and then the command to run. 

`$PORT` is an environment variable which is set by Heroku, you'll want to make sure your web applications are 
listening on this port as port 80 can't be bound. Don't worry, they'll still externally be available on port
80 (or 443 if you have SSL enabled).

## Your API Key

Take a note of your API key, which you can get [here](https://dashboard.heroku.com/account). You'll need this
later for CircleCI.

# Okay, now CircleCI

## Setting Up The Project

Navigate to the CircleCI Dashboard, then Projects. Find the repository you want, then click 'Set Up Project'.
You'll be presented with a bunch of options, but there's no Haskell option so pick `Use Existing Config`.

![](https://imgur.com/ojGwX6J.png)

## .circleci/config.yml

CircleCI depends on `.circleci/config.yml` being in your GitHub repository. We'll also use another script,
sourced from [this demo project](https://github.com/CircleCI-Public/circleci-demo-python-flask), to allow
CircleCI to talk to Heroku directly.

```yaml
version: 2.1
jobs:
  build:
    docker:
      - image: fpco/stack-build:lts-10.6
    working_directory: ~/app
    steps:
      - checkout
      - restore_cache:
          # Read about caching dependencies: https://circleci.com/docs/2.0/caching/
          name: Restore Cached Dependencies
          keys:
            - cci-demo-haskell-v1-{{ checksum "stack.yaml" }}-{{ checksum "hablog.cabal" }}
      - run:
          name: Workaround for GCC bug affecting static compilation
          command: |
            # More info about this workaround:
            # - https://www.fpcomplete.com/blog/2016/10/static-compilation-with-stack
            # - https://bugs.launchpad.net/ubuntu/+source/gcc-4.4/+bug/640734
            cp /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginT.o /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginT.o.orig
            cp /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginS.o /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginT.o
      - run:
          name: Configure Stack
          command: |
            stack config set system-ghc --global true
      - run:
          name: Statically compile Blog
          command: |
            stack --local-bin-path ~/app/dist install --ghc-options '-optl-static -fPIC'
      - run:
          name: Run tests
          command: |
            stack test
      - save_cache:
          name: Cache Dependencies
          key: cci-demo-haskell-v1-{{ checksum "stack.yaml" }}-{{ checksum "hablog.cabal" }}
          paths:
            - "/root/.stack"
            - ".stack-work"
      - store_artifacts:
          path: ~/app/dist
      - run:
          name: Setup Heroku
          command: bash .circleci/setup-heroku.sh
      - add_ssh_keys:
          fingerprints:
            - "34:e6:c0:32:7f:74:bf:19:0a:3a:09:52:e6:6e:12:52"
      - deploy:
          name: Deploy Master to Heroku
          command: |
            if [ "${CIRCLE_BRANCH}" == "master" ]; then
              git config --global user.email "your@email.com"
              git config --global user.name "Your Name"
              git add -f dist
              git commit -m "Deployment: Add dist folder"
              git push -f heroku master
            fi
```

To break it down a bit, first of all we have a `version: 2.1`. This tells CircleCI which version of their
API you're targetting. We have everything in a single job -- it could probably be split into two or three
but my aim was simplicity.

```yaml
docker:
  - image: fpco/stack-build-lts-10.6
```

This directive tells CircleCI that we want to build the project inside a Docker image, in this case a
specific version of Stack's LTS. fpco's [stack-build containers](https://hub.docker.com/r/fpco/stack-build)
come with GHC, Stack, Cabal, and everything else you need to compile a Stack package.

Next, we have a bunch of steps:

```
      - checkout
      - restore_cache:
          # Read about caching dependencies: https://circleci.com/docs/2.0/caching/
          name: Restore Cached Dependencies
          keys:
            - hablog-cache-{{ checksum "stack.yaml" }}-{{ checksum "hablog.cabal" }}
```

I would hope the `checkout` step is self-explanatory. The `restore_cache` step restores your dependencies
from a CircleCI cache, keyed against the checksum of `stack.yaml` and `hablog.cabal` (you'll need to change
the latter if you're not hosting Hablog).

```
      - run:
          name: Workaround for GCC bug affecting static compilation
          command: |
            # More info about this workaround:
            # - https://www.fpcomplete.com/blog/2016/10/static-compilation-with-stack
            # - https://bugs.launchpad.net/ubuntu/+source/gcc-4.4/+bug/640734
            cp /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginT.o /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginT.o.orig
            cp /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginS.o /usr/lib/gcc/x86_64-linux-gnu/5/crtbeginT.o
      - run:
          name: Configure Stack
          command: |
            stack config set system-ghc --global true
      - run:
          name: Statically compile Blog
          command: |
            stack --local-bin-path ~/app/dist install --ghc-options '-optl-static -fPIC'
      - run:
          name: Run tests
          command: |
            stack test
```

These steps are fairly self-explanatory, they set up stack and then compile the application. I'm not going
to go into detail on the GCC bug, but the links are included if you're curious.

```
      - save_cache:
          name: Cache Dependencies
          key: hablog-cache-{{ checksum "stack.yaml" }}-{{ checksum "hablog.cabal" }}
          paths:
            - "/root/.stack"
            - ".stack-work"
```

This step stores the dependencies as a cache so that they don't need to be re-downloaded every time. CircleCI
charges by the minute, so time-saving operations like this are definitely worth using.

```
      - store_artifacts:
          path: ~/app/dist
```

Next, we tell CircleCI to put our compiled artifact in the `app/dist` directory.

```
      - run:
          name: Setup Heroku
          command: bash .circleci/setup-heroku.sh
      - add_ssh_keys:
          fingerprints:
            - "34:e6:c0:32:7f:74:bf:19:0a:3a:09:52:e6:6e:12:52"
      - deploy:
          name: Deploy Master to Heroku
          command: |
            if [ "${CIRCLE_BRANCH}" == "master" ]; then
              git config --global user.email "your@email.com"
              git config --global user.name "Your Name"
              git add -f dist
              git commit -m "Deployment: Add dist folder"
              git push -f heroku master
            fi
```

These three steps handle deployment. We call a script (see below) to add the `heroku` remote to the Git
repository on CircleCI, then add the SSH fingerprint for Heroku's git server, then commit the `dist`
directory to the branch and push it to Heroku (don't worry, it won't be committed to your GitHub).

## .circleci/setup-heroku.sh

This script adds the Heroku remote, then stores a `.netrc` which will be used to log into Heroku.

```sh
#!/bin/bash
git remote add heroku https://git.heroku.com/$HEROKU_APP_NAME.git
wget https://cli-assets.heroku.com/branches/stable/heroku-linux-amd64.tar.gz
sudo mkdir -p /usr/local/lib /usr/local/bin
sudo tar -xvzf heroku-linux-amd64.tar.gz -C /usr/local/lib
sudo ln -s /usr/local/lib/heroku/bin/heroku /usr/local/bin/heroku

cat > ~/.netrc << EOF
machine api.heroku.com
  login $HEROKU_LOGIN
  password $HEROKU_API_KEY
machine git.heroku.com
  login $HEROKU_LOGIN
  password $HEROKU_API_KEY
EOF

# Add heroku.com to the list of known hosts
ssh-keyscan -H heroku.com >> ~/.ssh/known_hosts
```

## Environment Variables

Navigate to your project on CircleCI, then go to 'Project Settings'. You'll want to make sure these
are set up right for your specific project, and that's beyond the scope of this tutorial, then add some
environment variables:

- `HEROKU_API_KEY` should be set to your Heroku API key.
- `HEROKU_APP_NAME` should be set to your Heroku app name.
- `HEROKU_LOGIN` should be set to the e-mail address you used to sign up to Heroku.
