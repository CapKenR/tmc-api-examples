#!/usr/bin/env python3

import argparse
import requests
import json


parser = argparse.ArgumentParser(description='Pass in csp_token and tmc_url to make stream api call to event-service')
parser.add_argument('--csp_token', dest='csp_token', type=str, help='the csp api token to authenticate when calling event-servic stream api')
parser.add_argument('--tmc_url', dest='tmc_url', type=str, help='the url of the tmc org of which the events will be streamed')

args = parser.parse_args()


def call_event_stream_api():
    # get access token using csp_token
    response = requests.post('https://console.cloud.vmware.com/csp/gateway/am/api/auth/api-tokens/authorize?refresh_token=%s' % args.csp_token)
    try:
        access_token = response.json()['access_token']
    except:
        print ('Invalid csp_token. Please try again.')
        return

    # index to trim suffix in url. everything after .com will be removed
    try:
        trim_index = args.tmc_url.index('.com') + 4
    except:
        print ('Invalid tmc_url. Please try again.')
        return
    # trim url and add stream api suffix
    url = args.tmc_url[:trim_index] + '/v1alpha1/events/stream'

    # stream events from response
    try:
        response = requests.get(
            url,
            headers={'Authorization': 'Bearer %s' % access_token},
            stream=True
        )
        for line in response.iter_lines():
            print (line)
# There's a mysterious `b` at the beginning of each line.
# Line is in JSON format. Need to format or parse line.
# kdr            print (line.json())
# kdr            print (json.dumps(line, indent=4))
    except:
        return

if __name__ == '__main__':
    call_event_stream_api()

