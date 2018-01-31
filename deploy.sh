#! /bin/bash

# clone the repo
# cd into cloned repo

echo "=================="
echo "pip install pipenv"
echo "=================="
pip install pipenv

echo "=============="
echo "pipenv install"
echo "=============="
pipenv install

echo "============================================="
echo "pipenv run custodian run -s output policy.yml"
echo "============================================="
pipenv run custodian run -s output policy.yml
