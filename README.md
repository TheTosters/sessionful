# Useless DB

[![Pub Package](https://img.shields.io/pub/v/sessionful.svg)](https://pub.dev/packages/sessionful)
[![GitHub Issues](https://img.shields.io/github/issues/TheTosters/sessionful.svg)](https://github.com/TheTosters/sessionful/issues)
[![GitHub Forks](https://img.shields.io/github/forks/TheTosters/sessionful.svg)](https://github.com/TheTosters/sessionful/network)
[![GitHub Stars](https://img.shields.io/github/stars/TheTosters/sessionful.svg)](https://github.com/TheTosters/sessionful/stargazers)
[![GitHub License](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/TheTosters/sessionful/blob/master/LICENSE)

## What is it?

A library that allows you to create multiple communication channels over a single byte stream. This
allows to create smaller context sessions that are independent of each other. Session object is
payload independent. Encoding and decoding or payload is beyond the scope of this package.

## What is supported.

The API is very simple and limited to what I needed. It may (or may not) be extended in the future,
feel free to raise to raise a PR or FR on github.

- Create session with automatic generation of session ID
- Detect incoming new sessions.
- Ability to terminate session on demand (both sender - receiver side)
- push-pull support (send with request for response)
- Push + pull support (send without waiting for response, read response at any time)
- Check if there is any waiting data in the session.

## How to use

Please refer to the example for a very basic understanding of how it works. Then unit tests provide
much more examples of usage.