#!/usr/bin/env python3

# pylint: disable=missing-module-docstring
# pylint: disable=missing-class-docstring
# pylint: disable=missing-function-docstring
# pylint: disable=too-few-public-methods
# pylint: disable=too-many-arguments
# pylint: disable=too-many-instance-attributes

import inspect
from enum import Enum



def debug(*args):
    caller_frame = inspect.currentframe().f_back
    caller_filename = caller_frame.f_code.co_filename
    caller_lineno = caller_frame.f_lineno
    caller_name = caller_frame.f_code.co_name

    print(f"DEBUG: {caller_filename}:{caller_lineno} ({caller_name})")
    for arg in args:
        print(arg)

def reverse_map(source_map):
    result = {}
    for entry in source_map:
        result[source_map[entry]] = entry
    return result

directOnvifNamespaces = {
	"d": "http://schemas.xmlsoap.org/ws/2005/04/discovery",
	"dn": "http://www.onvif.org/ver10/network/wsdl",
	"SOAP-ENV": "http://www.w3.org/2003/05/soap-envelope",
	"tt": "http://www.onvif.org/ver10/schema",
	"tds": "http://www.onvif.org/ver10/device/wsdl",
	"timg": "http://www.onvif.org/ver20/imaging/wsdl",
	"trt": "http://www.onvif.org/ver10/media/wsdl",
	"tns1": "http://www.onvif.org/ver10/topics",
	"etns1": "http://elvees.com/onvif",
	"tev": "http://www.onvif.org/ver10/events/wsdl",
	"tptz": "http://www.onvif.org/ver20/ptz/wsdl",
	"trc": "http://www.onvif.org/ver10/recording/wsdl",
	"tan": "http://www.onvif.org/ver20/analytics/wsdl",
	"axt": "http://www.onvif.org/ver20/analytics",
	"wsa": "http://schemas.xmlsoap.org/ws/2004/08/addressing", # http://www.w3.org/2005/08/addressing
	"wstop": "http://docs.oasis-open.org/wsn/t-1",
	"wsnt": "http://docs.oasis-open.org/wsn/b-2",
	"xsd": "http://www.w3.org/2001/XMLSchema",
	"tae": "http://www.onvif.org/ver10/actionengine/wsdl",
	"tas": "http://www.onvif.org/ver10/advancedsecurity/wsdl",
	"ter": "http://www.onvif.org/ver10/error",
	#"wsse": "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
	#"wsdl": "http://www.onvif.org/ver20/media/wsdl",
}

reverseOnvifNamespaces = reverse_map(directOnvifNamespaces)

class TokenKind(Enum):
    NULL = 'null'
    WORD = 'word'
    SPACE = 'space'
    STRING = 'string'
    BINARY = 'binary'
    COMMENT = 'comment'
    PUNCT = 'punct'


class Token:
    @staticmethod
    def create_token(value, kind):
        return Token(value, kind, 0, len(value))

    def __init__(self, value, kind, pos, end):
        self.value = value
        self.kind = kind
        self.position = pos
        self.length = end - pos
        self.source = ""

    def is_null(self):
        return self.kind == TokenKind.NULL

    def is_space(self):
        return self.kind == TokenKind.SPACE

    def is_comment(self):
        return self.kind == TokenKind.COMMENT

    def is_any_word(self):
        return self.kind == TokenKind.WORD

    def is_word(self, value):
        return self.kind == TokenKind.WORD and self.length == len(value) and str(self) == value

    def is_punct(self, value):
        return self.kind == TokenKind.PUNCT and ord(self.source[self.position]) == ord(value[0])

    def is_string(self):
        return self.kind == TokenKind.STRING

    def is_binary(self):
        return self.kind == TokenKind.BINARY

    def string_before(self, from_token=None):
        if from_token:
            pos = from_token.position + from_token.length
            return self.source[pos:self.position]
        return self.source[:self.position]

    def string_after(self, to_token=None):
        end = self.position + self.length
        if to_token:
            return self.source[end:to_token.position]
        return self.source[end:]

    def to_info_string(self):
        if self.kind == TokenKind.NULL:
            return "nothing"
        return "'" + str(self) + "' (" + str(self.kind) + " type)"

class LexerConfig:
    def __init__(self, punctns_str, strings_str):
        self.punctns = {}
        self.strings = {}
        self.everytn = {}

        for character in enumerate(punctns_str):
            if character not in self.punctns:
                self.punctns[character] = 1
                self.everytn[character] = 1

        for character in enumerate(strings_str):
            if character not in self.strings and character not in self.punctns:
                self.strings[character] = 1
                self.everytn[character] = 1

golangLanguageConfig = LexerConfig('{}[]*', '"`')
golangCommentTagConfig = LexerConfig(':', '"`')
golangBinaryTagConfig = LexerConfig(':', '"')
golangXmlTagConfig = LexerConfig(',', '')

class Lexer:
    def __init__(self, source, line, config, offset=0, length=None):
        if length is None:
            length = len(source) - offset
        self.source = source
        self.pos = offset
        self.end = offset + length
        self.line = line
        self.punctns = config.punctns.copy()
        self.strings = config.strings.copy()
        self.everytn = config.everytn.copy()
        self.whitespaces = False
        self.next = None

    def skip_spaces(self):
        while self.pos < self.end and self.source[self.pos].isspace():
            self.pos += 1

    def get_token(self):
        if self.next is not None:
            token = self.next
            self.next = None
            return token

        self.skip_spaces()

        if self.pos >= self.end:
            return None

        token = self.parse_token()
        return token

    def peek_token(self):
        if self.next is None:
            self.skip_spaces()

            if self.pos >= self.end:
                return None

            self.next = self.parse_token()

        return self.next

    def skip_token(self):
        if self.next is not None:
            self.next = None
        else:
            self.skip_spaces()
            self.parse_token()

    def parse_token(self):
        if self.pos >= self.end:
            return None

        c = self.source[self.pos]
        self.pos += 1

        if c in self.punctns:
            return self.make_token('PUNCT', c)
        elif c in self.strings:
            return self.make_token('STRING', c)
        elif c in self.everytn:
            return self.make_token('EVERYTN', c)
        else:
            return self.make_token('UNKNOWN', c)

    def make_token(self, token_type, value):
        return {
            'type': token_type,
            'value': value,
            'line': self.line
        }