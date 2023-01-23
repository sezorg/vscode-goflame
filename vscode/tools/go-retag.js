#!/usr/bin/env node

const fs = require('fs');
const process = require('process');
const glob = require('glob'); // install: $ npm i glob
const child_process = require("child_process");

// Complete optimizations
const optimizationOptionsComplete = {
	// XML/SOAP/JSON
	omitTagNames: true, // Remove matching tag/key from configuration (safe). 
	transformNs: true, // Replace XML namespaces with their shorten XMLNS versions. 
	sortOptions: true, // Sort additional options, remove duplicates. 
	// JSON
	omitXmlInternals: true, // Remove xml.Name and over types from JSON RPC.
	derriveJsonKeys: true, // Derive JSON keys fro XML/SOAP tags.
	overrideJsonKeys: true, // Override JSON keys by values from XML/SOAP even they already exist.
	omitPointerTypes: true, // Make pointed types optional.
	omitArrayTypes: true, // Make array types optional.
	derriveOmitempty: true, // Use carefully: zero/null values will not be included into JSON.
}

const optimizationOptionsCurrent = {
	// XML/SOAP/JSON
	omitTagNames: false, // Remove matching tag/key from configuration (safe). 
	transformNs: false, // Replace XML namespaces with their shorten XMLNS versions. 
	sortOptions: false, // Sort additional options, remove duplicates. 
	// JSON
	omitXmlInternals: false, // Remove xml.Name and over types from JSON RPC.
	derriveJsonKeys: false, // Derive JSON keys fro XML/SOAP tags.
	overrideJsonKeys: false, // Override JSON keys by values from XML/SOAP even they already exist.
	omitPointerTypes: false, // Make pointed types optional.
	omitArrayTypes: false, // Make array types optional.
	derriveOmitempty: false, // Use carefully: zero/null values will not be included into JSON.
}

// Optimizations selector.
const optimizationOptions = optimizationOptionsCurrent;

const backupFilePostfix = ".bak";
const outputFilePostfix = ""; // ".out";
const logFileName = "go-retag.log";

const NUMBER_OF_SPACES = 4;
const TAB_REGEXP = new RegExp("\\t", "g");
const TAB_REPLACE = (" ").repeat(NUMBER_OF_SPACES);
const CHAR_CODE_SPACE = (' ').charCodeAt(0);
const TOKEN_NULL = 'null';
const TOKEN_WORD = 'word';
const TOKEN_SPACE = 'space';
const TOKEN_STRING = 'string';
const TOKEN_BINARY = 'binary';
const TOKEN_COMMENT = 'comment';
const TOKEN_PUNCT = 'punct';
const DEBUG_ENABLE = 0;

const specialNamespaces = {
	"xmlns": true,
	"xml": true,
}

const directOnvifNamespaces = {
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
	"wsa": "http://schemas.xmlsoap.org/ws/2004/08/addressing", // http://www.w3.org/2005/08/addressing
	"wstop": "http://docs.oasis-open.org/wsn/t-1",
	"wsnt": "http://docs.oasis-open.org/wsn/b-2",
	"xsd": "http://www.w3.org/2001/XMLSchema",
	"tae": "http://www.onvif.org/ver10/actionengine/wsdl",
	"tas": "http://www.onvif.org/ver10/advancedsecurity/wsdl",
	"ter": "http://www.onvif.org/ver10/error",
	//"wsse": "http://docs.oasis-open.org/wss/2004/01/oasis-200401-wss-wssecurity-secext-1.0.xsd",
	//"wsdl": "http://www.onvif.org/ver20/media/wsdl",
}

const reverseOnvifNamespaces = reverseMap(directOnvifNamespaces)

var unknonLongNs = [];
var unknonShortNs = [];
var unknonXmlnsNs = [];

function debug() {
	if (DEBUG_ENABLE) {
		console.debug(Array.from(arguments).join());
	}
}

function reverseMap(map) {
	var result = {};
	for (var entry in map) {
		result[map[entry]] = entry;
	}
	return result;
}

//
// class Token
//

class Token {
	constructor(source, type, pos, end) {
		this.type = type;
		this.source = source;
		this.position = pos;
		this.length = end - pos;
		this.vcache = null;
	}
	toString() {
		if (this.vcache === null) {
			this.vcache = this.source.substr(this.position, this.length);
		}
		return this.vcache;
	}
	toInfoString() {
		if (this.type === TOKEN_NULL) {
			return nothing;
		}
		return "'" + this.toString() + "' (" + this.type + " type)";
	}
	isNull() {
		return this.type === TOKEN_NULL;
	}
	isSpace() {
		return this.type === TOKEN_SPACE;
	}
	isComment() {
		return this.type === TOKEN_COMMENT;
	}
	isAnyWord() {
		return this.type === TOKEN_WORD;
	}
	isWord(value) {
		return this.type === TOKEN_WORD &&
			this.length === value.length &&
			this.toString() === value;
	}
	isPunct(value) {
		return this.type === TOKEN_PUNCT &&
			this.source.charCodeAt(this.position) === value.charCodeAt(0);
	}
	isString() {
		return this.type === TOKEN_STRING;
	}
	isBinary() {
		return this.type === TOKEN_BINARY;
	}
	stringBefore(fromToken) {
		if (fromToken) {
			var pos = fromToken.position + fromToken.length;
			return this.source.substr(pos, this.position - pos);
		}
		return this.source.substr(0, this.position);
	}
	stringAfter(toToken) {
		var end = this.position + this.length;
		if (toToken) {
			return this.source.substr(end, toToken.position - end);
		}
		return this.source.substr(end);
	}
}

Token.createToken = function (value, type) {
	return new Token(value, type, 0, value.length)
}

//
// class LexerConfig
//

class LexerConfig {
	constructor(punctnsStr, stringsStr) {
		this.punctns = {};
		this.strings = {};
		this.everytn = {};

		for (var index = 0; index < punctnsStr.length; index++) {
			var chr = punctnsStr.charCodeAt(index);
			if (!this.punctns[chr]) {
				this.punctns[chr] = 1;
				this.everytn[chr] = 1;
			}
		}

		for (var index = 0; index < stringsStr.length; index++) {
			var chr = stringsStr.charCodeAt(index);
			if (!this.strings[chr] && !this.punctns[chr]) {
				this.strings[chr] = 1;
				this.everytn[chr] = 1;
			}
		}
	}
}

const golangLanguageConfig = new LexerConfig('{}[]*', '"`');
const golangCommentTagConfig = new LexerConfig(':', '"`');
const golangBinaryTagConfig = new LexerConfig(':', '"');
const golangXmlTagConfig = new LexerConfig(',', '');

//
// class Lexer
//

class Lexer {
	constructor(source, line, config, offset, length) {
		if (offset === undefined) {
			offset = 0;
		}
		if (length === undefined) {
			length = source.length - offset;
		}
		this.source = source;
		this.pos = offset;
		this.end = offset + length;
		this.line = line;
		this.punctns = config.punctns;
		this.strings = config.strings;
		this.everytn = config.everytn;
		this.whitespaces = false;
		this.next = null;
	}
	skipSpaces() {
		while (this.pos < this.end && this.source.charCodeAt(pos) <= CHAR_CODE_SPACE) {
			this.pos++;
		}
	}
	getToken() {
		var result = this.peekToken();
		this.next = null;
		return result;
	}
	peekToken() {
		if (!this.next) {
			this.next = this.parseToken();
		}
		return this.next;
	}
	skipToken() {
		return this.getToken();
	}
	parseToken() {
		var self = this;
		var source = self.source;
		var pos = self.pos;
		var end = self.end;
		var sta = pos;

		function makeToken(type) {
			self.pos = pos;
			var token = new Token(source, type, sta, pos);
			//if (type !== TOKEN_NULL) {
			//	debug("Token type: " + token.type + ", value: '" + token.toString() + "'");
			//}
			return token;
		}

		while (pos < end && source.charCodeAt(pos) <= CHAR_CODE_SPACE) {
			pos++;
		}

		if (this.whitespaces && pos !== sta) {
			return makeToken(TOKEN_SPACE);
		}
		sta = pos;

		if (pos >= end) {
			return makeToken(TOKEN_NULL);
		}

		var chr = source.charCodeAt(pos);
		if (this.punctns[chr]) {
			pos++;
			return makeToken(TOKEN_PUNCT);
		}

		if (this.strings[chr]) {
			var type = TOKEN_STRING;
			if (chr === ('`').charCodeAt(0)) {
				type = TOKEN_BINARY;
			}
			pos++;
			while (pos < end) {
				if (source.charCodeAt(pos) === chr) {
					pos++;
					return makeToken(type);
				}
				pos++;
			}
			return makeToken(type);
		}

		if (chr === ('/').charCodeAt(0)) {
			if (pos + 1 < end && source.charCodeAt(pos + 1) === chr) {
				pos = end;
				return makeToken(TOKEN_COMMENT);
			}
		}

		while (pos < end) {
			chr = source.charCodeAt(pos);
			if (chr <= CHAR_CODE_SPACE || this.everytn[chr]) {
				break;
			}
			pos++;
		}
		return makeToken(TOKEN_WORD);
	}
}

//
// class GolangStructTagParser
//

class LineParser {
	constructor(source, index, fileInfo, silent) {
		this.source = source;
		this.index = index;
		this.fileInfo = fileInfo;
		this.tagList = [];
		this.tagMap = {};
		this.silent = silent;
		this.haveHeader = false;
		this.errorCount = 0;
		this.newSource = null;
	}

	emitMessage(token, continuation, message) {
		var self = this;

		function emit(string) {
			if (!self.silent) {
				self.fileInfo.log.write(string);
			}
		}

		if (!continuation) {
			if (!this.haveHeader || true) {
				this.haveHeader = true;
				emit("");
				emit("In \"" + this.fileInfo.fileName + ":" + (this.index + 1) + "\": type " +
					this.fileInfo.structDefinition.toString() + " struct:");
			}

			emit(this.source);
			if (token) {
				emit(("-").repeat(token.position) + "^");
			}
		}
		emit(message);
	}

	info(token, message) {
		this.emitMessage(token, false, "INFO: " + message);
	}

	info2(token, message) {
		this.emitMessage(token, true, "INFO: " + message);
	}

	warn(token, message) {
		this.emitMessage(token, false, "WARNING: " + message);
	}

	error(token, message) {
		this.errorCount++;
		this.fileInfo.log.errorCount++;
		this.emitMessage(token, false, "ERROR: " + message);
	}

	parse() {
		var lexer = new Lexer(
			this.source,
			this.index,
			golangLanguageConfig);

		var token = lexer.getToken();
		if (this.fileInfo.structDefinition === null) {
			if (token.isWord("type")) {
				var structName = lexer.getToken();
				token = lexer.getToken();
				if (token.isWord("struct")) {
					token = lexer.getToken();
					if (token.isPunct("{")) {
						token = lexer.getToken();
						if (token.isNull() || token.isComment()) {
							debug("struct " + structName.toString() + " {");
							this.fileInfo.structDefinition = structName;
						}
					}
				}
			}
			return;
		}

		if (token.isPunct("}")) {
			token = lexer.getToken();
			if (token.isNull() || token.isComment()) {
				this.fileInfo.structDefinition = null;
				debug("}");
			}
			return;
		}

		if (!this.fileInfo.structDefinition) {
			return;
		}

		var name = token;
		if (!name.isAnyWord()) {
			return;
		}

		var type = lexer.getToken();
		var isPointer = false;
		var isArray = false;
		if (type.isPunct("[") && lexer.peekToken().isPunct("]")) {
			isArray = true;
			lexer.skipToken();
			type = lexer.getToken();
		}
		if (type.isPunct("*")) {
			isPointer = true;
			type = lexer.getToken();
		}

		if (!type.isAnyWord()) {
			return;
		}

		var endOfType = type.position + type.length;
		token = lexer.getToken();
		var openA = 0;
		var openB = 0;
		var words = 0;

		function nothing() { }

		for (; ;) {
			if (token.isPunct("[")) {
				openA++;
			} else if (token.isPunct("]")) {
				openA--;
			} else if (token.isPunct("{")) {
				openB++;
			} else if (token.isPunct("}")) {
				openB--;
			} else if (token.isPunct("*")) {
				nothing();
			} else if (token.isAnyWord()) {
				if (words === 0) {
					if (token.isWord("map") ||
						token.isWord("interface") /*||
						token.isWord("struct") ||
						token.isWord("chan")*/) {
						isPointer = true;
					}
				}
				words++;
			} else {
				break;
			}
			endOfType = token.position + token.length;
			token = lexer.getToken();
		}

		if (openA !== 0 || openB !== 0) {

			if (openB === 1 && type.isWord("struct")) {
				this.error(token, "Inline struct declaration is not supported, consider to use substitution.");
			} else {

				this.error(token, "Opening and closing " +
					(openA !== 0 ? "brackets" : "braces") + " mismatch (" +
					(openA !== 0 ? openA : openB) + ").");
			}
			return;
		}

		type.length = endOfType - type.position;

		var tag = null;
		if (token.isBinary()) {
			tag = token;
			token = lexer.getToken();
		}

		var comment = null;
		var commentOrigin = null;
		var commentTag = null;
		if (!token.isNull()) {
			if (!token.isComment()) {
				this.error(token, "Comment or EOL expected, found " + token.toInfoString() + ".");
				return;
			}
			comment = token;
			var info = this.parseCommentTag(comment)
			if (info) {
				commentOrigin = info.origin;
				commentTag = info.tag;
			}
		}

		if (!tag && !commentTag) {
			return;
		}

		var declaration = {
			name: name,
			type: type,
			isPointer: isPointer,
			isArray: isArray,
			tag: tag,
			comment: comment,
			commentOrigin: commentOrigin,
			commentTag: commentTag
		}

		debug("Entry: " + name.toString() + " " +
			(isArray ? "[]" : "") +
			(isPointer ? "*" : "") +
			type.toString() + (tag ? " " + tag.toString() : "") +
			(comment ? " " + comment.toString() : ""));

		this.processItemDecl(declaration)
	}

	parseCommentTag(comment) {
		if (!comment) {
			return null;
		}

		var lexer = new Lexer(
			this.source,
			this.index,
			golangCommentTagConfig,
			comment.position + 2, // Skip '//'
			comment.length);

		var token = lexer.getToken();
		while (!token.isNull()) {
			if (token.isWord("origin") && lexer.peekToken().isPunct(":")) {
				lexer.skipToken();
				var tag = lexer.peekToken();
				if (tag.isBinary()) {
					return { origin: token, tag: tag };
				}
				this.warn(token, "Binary data expected after '" + token.toInfoString() + "'.");
			}
			token = lexer.getToken();
		}
		return null;
	}

	processItemDecl(declaration) {
		this.processTagConfigs(declaration);

		if(this.tagList.length == 0) {
			return;
		}

		var xmlConfig = this.processTagConfigByID("xml", true, 3);
		this.optimizeMarshalConfig(declaration, xmlConfig, null);

		var jsonConfig = this.processTagConfigByID("json", false, 2);
		this.optimizeMarshalConfig(declaration, jsonConfig, xmlConfig);

		var tomlConfig = this.processTagConfigByID("toml", false, 1);
		this.optimizeMarshalConfig(declaration, tomlConfig, null);

		if (this.errorCount !== 0) {
			return;
		}

		this.tagList.sort(function (tagConfigA, tagConfigB) {
			return tagConfigB.weight - tagConfigA.weight;
		});

		var modified = false;
		this.tagList.every(function (tagConfig) {
			if (tagConfig.emitResult) {
				modified = true;
				return false;
			}
			return true;
		});

		var tag = declaration.tag;
		var comment = declaration.comment;
		if (modified) {
			var modifiedTag = "";
			this.tagList.every(function (tagConfig) {
				var appendValue = tagConfig.emitResult ?
					tagConfig.emitResult :
					tagConfig.data.toString();
				if (appendValue.length > 2) {
					if (modifiedTag.length !== 0) {
						modifiedTag += " ";
					}
					modifiedTag += tagConfig.id.toString() + ":" + appendValue;
				}
				return true;
			});

			if (modifiedTag.length) {
				modifiedTag = "`" + modifiedTag + "`";
			}

			var tagString = tag ? tag.toString() : "";
			if (tagString !== modifiedTag) {

				var commentPrefix = " ";
				var commentString = "//";
				if (comment) {
					commentPrefix = "";
					commentString = comment.toString();
				}

				if (!declaration.commentTag) {
					commentString = commentString.trim() + " origin:" + tagString;
				}

				if (tag) {
					this.newSource = tag.stringBefore() + modifiedTag +
						tag.stringAfter(comment) + commentPrefix + commentString;
				} else if (comment) {
					this.newSource = comment.stringBefore().trimRight() +
						" " + modifiedTag + " " + commentPrefix + commentString;
				} else {
					this.newSource = this.source.trimRight() +
						" " + modifiedTag + " " + commentPrefix + commentString;
				}
			} 
		} else if (comment) {
			var commentOrigin = declaration.commentOrigin;
			var commentTag = declaration.commentTag;
			if (commentOrigin && commentTag) {
				var newComment = commentOrigin.stringBefore(comment) + commentTag.stringAfter();
				newComment = newComment.replace(/\s\s/g, ' ').trim();
				if (newComment === "//") {
					newComment = "";
				}
				if (tag) {
					this.newSource = tag.stringBefore() + commentTag + tag.stringAfter(comment) + newComment;
				} else {
					this.newSource = comment.stringBefore().trimRight() + " " + commentTag + newComment;
				}
			}
		}
		if (this.newSource === this.source) {
			this.newSource = null;
		} else {
			debug(null, "Source old: " + this.source);
			debug(null, "Source new: " + this.newSource);
		}
}

	processTagConfigByID(typeId, allowNamespace, assignWight) {
		var tagConfig = this.tagMap[typeId];
		if (tagConfig) {
			this.processMarshalConfig(tagConfig, allowNamespace);
		} else {
			tagConfig = this.createTagConfig(
				Token.createToken(typeId, TOKEN_WORD),
				Token.createToken("\"\"", TOKEN_STRING), false);
		}
		tagConfig.weight = assignWight;
		return tagConfig;
	}

	createTagConfig(id, data, present) {
		var idString = id.toString();
		var tagConfig = this.tagMap[idString];
		if (tagConfig) {
			this.error(id, "Duplicate tag identifiers '" + idString + "'.");
		} else {
			tagConfig = {
				weight: 0,
				id: id,
				data: data,
				present: present,
				namespace: null,
				tagName: null,
				options: [],
				emitResult: null,
				emitName: null,
			}
			this.tagList.push(tagConfig);
			this.tagMap[idString] = tagConfig;
		}
		return tagConfig;
	}

	processTagConfigs(declaration) {
		var tag = declaration.tag;
		if (declaration.commentTag) {
			tag = declaration.commentTag;
		}

		if (!tag) {
			return;
		}

		var lexer = new Lexer(
			this.source,
			this.line,
			golangBinaryTagConfig,
			tag.position + 1, // Skip binary prefix  '`'
			tag.length - 2);

		for (; ;) {
			var id = lexer.getToken();
			if (id.isNull()) {
				return;
			}

			if (!id.isAnyWord()) {
				this.error(id, "Tag identifier expected, found " + id.toInfoString() + ".");
				break;
			}

			var token = lexer.getToken();
			if (!token.isPunct(":")) {
				this.error(token, "Separator ':' expected ater tag '" + id.toString() +
					"', found " + token.toInfoString() + ".");
				break;
			}

			var data = lexer.getToken();
			if (!data.isString()) {
				this.error(data, "Configuration string expected for '" + id.toString() +
					"', found " + data.toInfoString() + ".");
				break;
			}

			this.createTagConfig(id, data, true);
		}
	}

	processMarshalConfig(tagConfig, allowNamespace) {
		var lexer = new Lexer(
			this.source,
			this.line,
			golangXmlTagConfig,
			tagConfig.data.position + 1,
			tagConfig.data.length - 2);

		var token = lexer.getToken();
		if (token.isNull()) {
			this.error(token, "An empty configuration string.");
			return null;
		}

		if (allowNamespace) {
			lexer.whitespaces = true;
			var second = lexer.peekToken();
			lexer.whitespaces = false;

			if (second.isSpace() && token.isAnyWord()) {
				tagConfig.namespace = token;
				lexer.skipToken();
				token = lexer.getToken();
			}
		}

		if (token.isAnyWord()) {
			tagConfig.tagName = token;
			token = lexer.getToken();
		}

		if (token.isNull()) {
			return tagConfig;
		}

		for (; ;) {
			if (!token.isPunct(",")) {
				this.error(token, "Comma separator ',' expected, found " + token.toInfoString() + ".");
				break;
			}

			do {
				token = lexer.getToken();
			} while (token.isPunct(","));
			if (token.isNull()) {
				return tagConfig;
			}

			if (!token.isAnyWord()) {
				this.error(token, "Option identifier expected, found " + token.toInfoString() + ".");
				break;
			}

			tagConfig.options.push(token.toString());
			token = lexer.getToken();
			if (token.isNull()) {
				return tagConfig;
			}
		}
		return null;
	}

	optimizeMarshalConfig(declaration, tagConfig, xmlConfig) {
		var self = this;

		debug("XMLConfig:" +
			" namespace: " + (tagConfig.namespace ? tagConfig.namespace.toString() : "null") +
			" tagName: " + (tagConfig.tagName ? tagConfig.tagName.toString() : "null") +
			" options: [" + tagConfig.options.join(",") + "]");

		var namespace = tagConfig.namespace ? tagConfig.namespace.toString() : null;
		var newNamespace = namespace;
		var tagName = tagConfig.tagName ? tagConfig.tagName.toString() : null;
		var newTagName = tagName;

		var newOptionsChanged = false;
		var newOptions = [...tagConfig.options];
		var tagPoint = tagConfig.tagName ? tagConfig.tagName : tagConfig.id;

		var shortNs = null;
		if (namespace) {
			shortNs = reverseOnvifNamespaces[namespace];
			if (!shortNs) {
				if (unknonLongNs.indexOf(namespace) < 0) {
					unknonLongNs.push(namespace);
					this.warn(tagConfig.namespace, "Can not find short NS for '" + namespace + "'.");
				}
			}
		}

		function applyShortNs() {
			if (shortNs && optimizationOptions.transformNs) {
				newNamespace = null;
				newTagName = shortNs + ":" + pureTagName;
				self.info(tagPoint, "Short namespace '" + shortNs + "' applied to '" + pureTagName + "'.");
			}
		}

		const declName = declaration.name.toString();
		var pureTagName = declName;

		//
		// Process XML namespaces.
		//

		if (tagName) {
			var pureTagNs = "";
			pureTagName = tagName;
			var separator = tagName.indexOf(":");
			if (separator >= 0) {
				pureTagNs = tagName.substr(0, separator);
				pureTagName = tagName.substr(separator + 1);
				if (pureTagName === "") {
					this.warn(tagPoint, "An empty tag name after NS.");
					pureTagName = declName;
				}
			}

			if (pureTagName === "-") {
				newTagName = "-";
				if (optimizationOptions.transformNs && newNamespace !== null) {
					newNamespace = null;
					this.info(tagPoint, "Removing unnecessary namespace '" + newNamespace + "'.");
				}
			} else if (pureTagNs.length !== 0) {
				if (!directOnvifNamespaces[pureTagNs]) {
					if (!specialNamespaces[pureTagNs]) {
						if (unknonShortNs.indexOf(pureTagNs) < 0) {
							unknonShortNs.push(pureTagNs);
							this.warn(tagPoint, "Unknown short namespace in tag '" + pureTagNs + "'.");
						}
					} else if (pureTagNs === "xmlns") {
						if (!directOnvifNamespaces[pureTagName]) {
							if (unknonXmlnsNs.indexOf(pureTagName) < 0) {
								unknonXmlnsNs.push(pureTagName);
								this.warn(tagPoint, "Short XMLNS namespace '" + pureTagName + "' is not registered.");
							}
						}
					}
				}
				if (optimizationOptions.transformNs && newNamespace !== null) {
					newNamespace = null;
					this.info(tagPoint, "Removing unnecessary namespace '" + newNamespace + "'.");
				}
			} else if (namespace) {
				applyShortNs();
			} else if (pureTagName === declName) {
				if (optimizationOptions.omitTagNames) {
					newTagName = null;
					this.info(tagPoint, "Tag name '" + pureTagName + "' matches declaration and can be removed.");
				}
			}
		} else {
			if (namespace) {
				applyShortNs();
			}
		}
		const emitName = pureTagName;
		tagConfig.emitName = emitName;

		//
		// Additional JSON postprocessing.	
		//

		if (xmlConfig) {
			var tagPoint = tagConfig.present ?
				(tagConfig.tagName ? tagConfig.tagName : tagConfig.id) :
				(xmlConfig.tagName ? xmlConfig.tagName : xmlConfig.id);
			var declType = declaration.type.toString();
			var internalType = false;
			if (declType === "xml.Name") {
				internalType = true;
			}

			var omitted = false;
			if (optimizationOptions.omitXmlInternals) {
				if (internalType) {
					newTagName = "-";
					newNamespace = null;
					newOptions = [];
					newOptionsChanged = true;
					omitted = true;
					this.info(declaration.type, "JSON internal XML/SOAP implementation type '" + declType + "' has been omitted.");
				}
			}

			if (!omitted) {
				// Derrive config from XML/SOAP.
				if (!internalType && xmlConfig.present) {
					var xmlEmitName = xmlConfig.emitName;
					if (optimizationOptions.derriveJsonKeys && xmlEmitName !== emitName) {
						if (optimizationOptions.overrideJsonKeys || !tagName) {
							newTagName = xmlEmitName;
							var prefix = tagName ? "" : "Imaginary ";
							if (xmlEmitName === "-") {
								this.info(tagPoint, prefix + "JSON key is hidden by XML/SOAP settings.");
							} else {
								if (1 || tagName !== newTagName) {
									this.info(tagPoint, prefix + "JSON key '" + emitName + "' is overriden by XML/SOAP tag '" + xmlEmitName + "'.");
								}
							}
						} else
							if (xmlEmitName === "-") {
								this.warn(tagPoint, "Visible JSON key '" + tagName + " is hidden by XML/SOAP settings.");
							} else if (tagName === "-") {
								this.warn(tagPoint, "Visible XML/SOAP tag '" + xmlEmitName + " is hidden by JSON settings.");
							} else {
								this.warn(tagPoint, "Specified JSON key '" + tagName + "' differs from XML/SOAP tag '" + xmlEmitName + "'.");
							}

					}
				}
			}

			if (optimizationOptions.derriveOmitempty && xmlConfig.options.indexOf("omitempty") >= 0 &&
				newOptions.indexOf("omitempty") < 0) {
				newOptions.push("omitempty");
				newOptionsChanged = true;
				this.info(tagPoint, "JSON 'omitempty' flag is derrived from XML/JSOAP config.");
			}

			// Omit empty pointed types.
			if ((declaration.isPointer && optimizationOptions.omitPointerTypes) ||
				(declaration.isArray && optimizationOptions.omitArrayTypes)) {
				if (newOptions.indexOf("omitempty") < 0) {
					newOptions.push("omitempty");
					newOptionsChanged = true;
					this.info(tagPoint, "Added JSON 'omitempty' flag for pointed/array type.");
				}
			}
		}

		//
		// Finalize changes.
		//

		if (optimizationOptions.sortOptions || newOptionsChanged) {
			var seen = {};
			newOptions = newOptions.filter(function (item) {
				return seen.hasOwnProperty(item) ? false : (seen[item] = true);
			});
			newOptions.sort();
		}
		newOptionsChanged = !(newOptions.length === tagConfig.options.length &&
			newOptions.every((element, index) => element === tagConfig.options[index]));

		if (optimizationOptions.omitTagNames && newTagName === declName) {
			newTagName = null;
			this.info(tagPoint, "Tag name '" + pureTagName + "' matches declaration and can be removed.");
		}

		if (newOptionsChanged || namespace !== newNamespace || tagName !== newTagName) {
			var emitResult = "";
			if (newNamespace) {
				emitResult = newNamespace;
			}

			if (newTagName) {
				if (emitResult.length !== 0) {
					emitResult += " ";
				}
				emitResult += newTagName;
			}

			if (newOptions.length !== 0) {
				newOptions.sort();
				emitResult += "," + newOptions.join(",");
			}

			emitResult = "\"" + emitResult + "\"";
			tagConfig.emitResult = emitResult;
			debug("Optimized from: " + tagConfig.id.toString() + ":" + tagConfig.data.toString());
			debug("Optimized to:   " + tagConfig.id.toString() + ":" + emitResult);
		}
	}
}

class FileParser {
	constructor(fileName, log) {
		this.fileName = fileName;
		this.log = log;
		this.structDefinition = null;
	}
	parse(readonlyMode) {
		var textModified = false;
		var text = fs.readFileSync(this.fileName).toString().split("\n");
		for (var index = 0; index < text.length; index++) {
			var line = text[index];
			var tabLine = line.replace(TAB_REGEXP, TAB_REPLACE);

			var parser = new LineParser(tabLine, index, this, false);
			parser.parse();
			if (parser.newSource) {
				parser = new LineParser(line, index, this, true);
				parser.parse();
				if (!parser.newSource) {
					parser.silent = false;
					parser.error("Fatal. Failed to parse source line.");
				} else {
					textModified = true;
					text[index] = parser.newSource;
				}
			}
		}

		if (textModified && !readonlyMode) {
			var backupName = this.fileName + backupFilePostfix;
			if (!fs.existsSync(backupName)) {
				try {
					fs.copyFileSync(this.fileName, backupName);
				} catch (e) {
					this.log.error("Unable to creatre backup file '" + backupName + "': " + e + ".");
					return;
				}
			}

			var outputName = this.fileName + outputFilePostfix;
			var textData = text.join("\n");
			try {
				var fd = fs.openSync(outputName, 'w', 0o666);
				fs.writeSync(fd, textData);
				fs.closeSync(fd);
			} catch (e) {
				this.log.error("Unable to write file '" + outputName + "': " + e + ".");
				return;
			}

			try {
				child_process.exec("gofmt -w " + outputName);
			} catch (e) {
				this.log.error("Unable to execute 'gofmt' on file '" + outputName + "': " + e + ".");
				return;
			}
		}
	}
}

class LogFile {
	constructor(fileName) {
		this.fileName = fileName;
		this.fd = fs.openSync(fileName, 'w', 0o666);
		this.infoCount = 0;
		this.warnCount = 0;
		this.errorCount = 0;
	}

	write() {
		for (var index = 0; index < arguments.length; index++) {
			var message = arguments[index];
			console.info(message);
			fs.writeSync(this.fd, arguments[index]);
			fs.writeSync(this.fd, "\n");
		}
	}

	info(message) {
		this.infoCount++;
		this.write("INFO: " + message);
	}

	warn(message) {
		this.write("WARNING: " + message);
	}

	error(message) {
		this.errorCount++;
		this.write("ERROR: " + message);
	}
}

function execute() {
	glob("**/*.go", processFiles)

	function processFiles(error, files) {
		if (error) {
			console.log(error)
			return
		}

		var log = new LogFile(logFileName);
		log.write("Started " + new Date().toISOString());

		for (var index = 0; index < files.length; index++) {
			var fileName = files[index];
			var file = new FileParser(fileName, log);
			file.parse(false);
		}
	}
}

execute()
