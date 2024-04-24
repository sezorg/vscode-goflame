#! /usr/bin/env python3

# Complete optimizations
optimizationOptionsComplete = {
	# XML/SOAP/JSON
	omitTagNames: True, # Remove matching tag/key from configuration (safe).
	transformNs: False, # Replace XML namespaces with their shorten XMLNS versions.
	sortOptions: True, # Sort additional options, remove duplicates.
	# JSON
	omitXmlInternals: True, # Remove xml.Name and over types from JSON RPC.
	derriveJsonKeys: True, # Derive JSON keys fro XML/SOAP tags.
	overrideJsonKeys: True, # Override JSON keys by values from XML/SOAP even they already exist.
	omitPointerTypes: True, # Make pointed types optional.
	omitArrayTypes: True, # Make array types optional.
	derriveOmitempty: True, # Use carefully: zero/null values will not be included into JSON.
	# Overall
	saveTagsComments: False, # Save original structure tags in comments
}

optimizationOptionsCurrent = {
	# XML/SOAP/JSON
	omitTagNames: False, # Remove matching tag/key from configuration (safe).
	transformNs: False, # Replace XML namespaces with their shorten XMLNS versions.
	sortOptions: False, # Sort additional options, remove duplicates.
	# JSON
	omitXmlInternals: False, # Remove xml.Name and over types from JSON RPC.
	derriveJsonKeys: False, # Derive JSON keys fro XML/SOAP tags.
	overrideJsonKeys: False, # Override JSON keys by values from XML/SOAP even they already exist.
	omitPointerTypes: False, # Make pointed types optional.
	omitArrayTypes: False, # Make array types optional.
	derriveOmitempty: False, # Use carefully: zero/null values will not be included into JSON.
	# Overall
	saveTagsComments: False, # Save original structure tags in comments
}

# Optimizations selector.
const optimizationOptions = optimizationOptionsComplete

const backupFilePostfix = ".bak"
const outputFilePostfix = ""; # ".out";
const logFileName = "go-retag.log"

const NUMBER_OF_SPACES = 4
const TAB_REGEXP = new RegExp("\\t", "g")
const TAB_REPLACE = (" ").repeat(NUMBER_OF_SPACES)
const CHAR_CODE_SPACE = (' ').charCodeAt(0)
const TOKEN_NULL = 'null'
const TOKEN_WORD = 'word'
const TOKEN_SPACE = 'space'
const TOKEN_STRING = 'string'
const TOKEN_BINARY = 'binary'
const TOKEN_COMMENT = 'comment'
const TOKEN_PUNCT = 'punct'
const DEBUG_ENABLE = True
const CREATE_BACKUP = False

const specialNamespaces = {
	"xmlns": True,
	"xml": True,
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
	"wsa": "http://schemas.xmlsoap.org/ws/2004/08/addressing", # http://www.w3.org/2005/08/addressing
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

var unknonLongNs = []
var unknonShortNs = []
var unknonXmlnsNs = []

def debug(*args):
    caller_frame = inspect.currentframe().f_back
    caller_filename = caller_frame.f_code.co_filename
    caller_lineno = caller_frame.f_lineno
    caller_name = caller_frame.f_code.co_name

    print(f"DEBUG: {caller_filename}:{caller_lineno} ({caller_name})")
    for arg in args:
        print(arg)

def reverse_map(map):
    result = {}
    for entry in map:
        result[map[entry]] = entry
    return result

#
# class Token
#

class Token
	def __init__(self, source, type, pos, end):
		this.type = type
		this.source = source
		this.position = pos
		this.length = end - pos
		this.vcache = None

	def toString():
		if this.vcache is None:
			this.vcache = this.source.substr(this.position, this.length)

		return this.vcache

	toInfoString(:
		if this.type is TOKEN_NULL:
			return nothing

		return "'" + this.toString() + "' (" + this.type + " type)"

	isNull(:
		return this.type is TOKEN_NULL

	isSpace(:
		return this.type is TOKEN_SPACE

	isComment(:
		return this.type is TOKEN_COMMENT

	isAnyWord(:
		return this.type is TOKEN_WORD

	isWord(value:
		return this.type is TOKEN_WORD &&
			this.length is value.length &&
			this.toString() is value

	isPunct(value:
		return this.type is TOKEN_PUNCT &&
			this.source.charCodeAt(this.position) is value.charCodeAt(0)

	isString(:
		return this.type is TOKEN_STRING

	isBinary(:
		return this.type is TOKEN_BINARY

	stringBefore(fromToken:
		if fromToken:
			var pos = fromToken.position + fromToken.length
			return this.source.substr(pos, this.position - pos)

		return this.source.substr(0, this.position)

	stringAfter(toToken:
		var end = this.position + this.length
		if toToken:
			return this.source.substr(end, toToken.position - end)

		return this.source.substr(end)

}

Token.createToken = def (value, type):
	return new Token(value, type, 0, value.length)


//
# class LexerConfig
//

class LexerConfig {
	constructor(punctnsStr, stringsStr:
		this.punctns = {}
		this.strings = {}
		this.everytn = {}

		for var index = 0; index < punctnsStr.length; index++:
			var chr = punctnsStr.charCodeAt(index)
			if not this.punctns[chr]:
				this.punctns[chr] = 1
				this.everytn[chr] = 1



		for var index = 0; index < stringsStr.length; index++:
			var chr = stringsStr.charCodeAt(index)
			if not this.strings[chr] and not this.punctns[chr]:
				this.strings[chr] = 1
				this.everytn[chr] = 1



}

const golangLanguageConfig = new LexerConfig('{}[]*', '"`')
const golangCommentTagConfig = new LexerConfig(':', '"`')
const golangBinaryTagConfig = new LexerConfig(':', '"')
const golangXmlTagConfig = new LexerConfig(',', '')

//
# class Lexer
//

class Lexer {
	constructor(source, line, config, offset, length:
		if offset is Unset:
			offset = 0

		if length is Unset:
			length = source.length - offset

		this.source = source
		this.pos = offset
		this.end = offset + length
		this.line = line
		this.punctns = config.punctns
		this.strings = config.strings
		this.everytn = config.everytn
		this.whitespaces = False
		this.next = None

	skipSpaces(:
		while this.pos < this.end and this.source.charCodeAt(pos) <= CHAR_CODE_SPACE:
			this.pos++


	getToken(:
		var result = this.peekToken()
		this.next = None
		return result

	peekToken(:
		if not this.next:
			this.next = this.parseToken()

		return this.next

	skipToken(:
		return this.getToken()

	parseToken(:
		var self = this
		var source = self.source
		var pos = self.pos
		var end = self.end
		var sta = pos

		def makeToken(type):
			self.pos = pos
			var token = new Token(source, type, sta, pos)
			//if type is not TOKEN_NULL:
			//	debug("Token type: " + token.type + ", value: '" + token.toString() + "'")
			//
			return token


		while pos < end and source.charCodeAt(pos) <= CHAR_CODE_SPACE:
			pos++


		if this.whitespaces and pos is not sta:
			return makeToken(TOKEN_SPACE)

		sta = pos

		if pos >= end:
			return makeToken(TOKEN_NULL)


		var chr = source.charCodeAt(pos)
		if this.punctns[chr]:
			pos++
			return makeToken(TOKEN_PUNCT)


		if this.strings[chr]:
			var type = TOKEN_STRING
			if chr is ('`').charCodeAt(0):
				type = TOKEN_BINARY

			pos++
			while pos < end:
				if source.charCodeAt(pos) is chr:
					pos++
					return makeToken(type)

				pos++

			return makeToken(type)


		if chr is ('/').charCodeAt(0):
			if pos + 1 < end and source.charCodeAt(pos + 1) is chr:
				pos = end
				return makeToken(TOKEN_COMMENT)



		while pos < end:
			chr = source.charCodeAt(pos)
			if chr <= CHAR_CODE_SPACEor this.everytn[chr]:
				break

			pos++

		return makeToken(TOKEN_WORD)

}

//
# class GolangStructTagParser
//

class LineParser {
	constructor(source, index, fileInfo, silent:
		this.source = source
		this.index = index
		this.fileInfo = fileInfo
		this.tagList = []
		this.tagMap = {}
		this.tagMapSize = 0
		this.silent = silent
		this.haveHeader = False
		this.errorCount = 0
		this.newSource = None


	emitMessage(token, continuation, message:
		var self = this

		def emit(string):
			if not self.silent:
				self.fileInfo.log.write(string)



		if not continuation:
			if not this.haveHeaderor True:
				this.haveHeader = True
				emit("")
				emit("In \"" + this.fileInfo.fileName + ":" + (this.index + 1) + "\": type " +
					this.fileInfo.structDefinition.toString() + " struct:")


			emit(this.source)
			if token:
				emit(("-").repeat(token.position) + "^")


		emit(message)


	info(token, message:
		this.emitMessage(token, False, "INFO: " + message)


	info2(token, message:
		this.emitMessage(token, True, "INFO: " + message)


	warn(token, message:
		this.emitMessage(token, False, "WARNING: " + message)


	error(token, message:
		this.errorCount++
		this.fileInfo.log.errorCount++
		this.emitMessage(token, False, "ERROR: " + message)


	parse(:
		var lexer = new Lexer(
			this.source,
			this.index,
			golangLanguageConfig)

		var token = lexer.getToken()
		if this.fileInfo.structDefinition is None:
			if token.isWord("type"):
				var structName = lexer.getToken()
				token = lexer.getToken()
				if token.isWord("struct"):
					token = lexer.getToken()
					if token.isPunct("{"):
						token = lexer.getToken()
						if token.isNull()or token.isComment():
							debug("struct " + structName.toString() + " {")
							this.fileInfo.structDefinition = structName




			return


		if token.isPunct("}"):
			token = lexer.getToken()
			if token.isNull()or token.isComment():
				this.fileInfo.structDefinition = None
				debug("}")

			return


		if not this.fileInfo.structDefinition:
			return


		var name = token
		if not name.isAnyWord():
			return


		var type = lexer.getToken()
		var isPointer = False
		var isArray = False
		if type.isPunct("[") and lexer.peekToken().isPunct("]"):
			isArray = True
			lexer.skipToken()
			type = lexer.getToken()

		if type.isPunct("*"):
			isPointer = True
			type = lexer.getToken()


		if not type.isAnyWord():
			return


		var endOfType = type.position + type.length
		token = lexer.getToken()
		var openA = 0
		var openB = 0
		var words = 0

		def nothing() { }

		for ; ;):
			if token.isPunct("["):
				openA++
			elif token.isPunct("]"):
				openA--
			elif token.isPunct("{"):
				openB++
			elif token.isPunct("}"):
				openB--
			elif token.isPunct("*"):
				nothing()
			elif token.isAnyWord():
				if words is 0:
					if token.isWord("map") ||
						token.isWord("interface") /*||
						token.isWord("struct") ||
						token.isWord("chan")*/:
						isPointer = True


				words++
			else:
				break

			endOfType = token.position + token.length
			token = lexer.getToken()


		if openA is not 0or openB is not 0:

			if openB is 1 and type.isWord("struct"):
				this.error(token, "Inline struct declaration is not supported, consider to use substitution.")
			else:

				this.error(token, "Opening and closing " +
					(openA is not 0 ? "brackets" : "braces") + " mismatch (" +
					(openA is not 0 ? openA : openB) + ").")

			return


		type.length = endOfType - type.position

		var tag = None
		if token.isBinary():
			tag = token
			token = lexer.getToken()


		var comment = None
		var commentOrigin = None
		var commentTag = None
		if not token.isNull():
			if not token.isComment():
				this.error(token, "Comment or EOL expected, found " + token.toInfoString() + ".")
				return

			comment = token
			var info = this.parseCommentTag(comment)
			if info:
				commentOrigin = info.origin
				commentTag = info.tag



		if not tag and not commentTag:
			return


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
			(comment ? " " + comment.toString() : ""))

		this.processItemDecl(declaration)


	parseCommentTag(comment:
		if not comment:
			return None


		var lexer = new Lexer(
			this.source,
			this.index,
			golangCommentTagConfig,
			comment.position + 2, # Skip '//'
			comment.length)

		var token = lexer.getToken()
		while not token.isNull():
			if token.isWord("origin") and lexer.peekToken().isPunct(":"):
				lexer.skipToken()
				var tag = lexer.peekToken()
				if tag.isBinary():
					return { origin: token, tag: tag }

				this.warn(token, "Binary data expected after '" + token.toInfoString() + "'.")

			token = lexer.getToken()

		return None


	processItemDecl(declaration:
		this.processTagConfigs(declaration)

		if(this.tagList.length == 0:
			return


		var xmlConfig = this.processTagConfigByID("xml", True, 3)
		this.optimizeMarshalConfig(declaration, xmlConfig, None)

		var jsonConfig = this.processTagConfigByID("json", False, 2)
		this.optimizeMarshalConfig(declaration, jsonConfig, xmlConfig)

		var tomlConfig = this.processTagConfigByID("toml", False, 1)
		this.optimizeMarshalConfig(declaration, tomlConfig, None)

		if this.errorCount is not 0:
			return


		this.tagList.sort(def (tagConfigA, tagConfigB):
			return tagConfigB.weight - tagConfigA.weight
		)

		var modified = False
		this.tagList.every(def (tagConfig):
			if tagConfig.emitResult:
				modified = True
				return False

			return True
		)

		var tag = declaration.tag
		var comment = declaration.comment
		if modified:
			var modifiedTag = ""
			this.tagList.every(def (tagConfig):
				var appendValue = tagConfig.emitResult ?
					tagConfig.emitResult :
					tagConfig.data.toString()
				if appendValue.length > 2) {
					if modifiedTag.length is not 0:
						modifiedTag += " "

					modifiedTag += tagConfig.id.toString() + ":" + appendValue
				}
				return True
			)

			if modifiedTag.length:
				modifiedTag = "`" + modifiedTag + "`"


			var tagString = tag ? tag.toString() : ""
			if tagString is not modifiedTag:

				var commentPrefix = " "
				var commentString = ""
				if comment:
					commentPrefix = ""
					commentString = comment.toString()
				 else if(optimizationOptions.saveTagsComments:
					commentString = "//"


				if not declaration.commentTag and optimizationOptions.saveTagsComments:
					commentString = commentString.trim() + " origin:" + tagString


				if tag:
					this.newSource = tag.stringBefore() + modifiedTag +
						tag.stringAfter(comment)
					if commentString not = "":
						this.newSource += commentPrefix + commentString

				elif comment:
					this.newSource = comment.stringBefore().trimRight() + " " + modifiedTag
					if commentString not = "":
						this.newSource += " " + commentPrefix + commentString

				else:
					this.newSource = this.source.trimRight() + " " + modifiedTag
					if commentString not = "":
						this.newSource += " " + commentPrefix + commentString


			}
		elif comment:
			var commentOrigin = declaration.commentOrigin
			var commentTag = declaration.commentTag
			if commentOrigin and commentTag:
				var newComment = commentOrigin.stringBefore(comment) + commentTag.stringAfter()
				newComment = newComment.replace(/\s\s/g, ' ').trim()
				if newComment is "//":
					newComment = ""

				if tag:
					this.newSource = tag.stringBefore() + commentTag + tag.stringAfter(comment) + newComment
				else:
					this.newSource = comment.stringBefore().trimRight() + " " + commentTag + newComment


		}
		if this.newSource is this.source:
			this.newSource = None
		else:
			debug("Source old: " + this.source)
			debug("Source new: " + this.newSource)

}

	processTagConfigByID(typeId, allowNamespace, assignWight:
		var tagConfig = this.tagMap[typeId]
		if tagConfig:
			this.processMarshalConfig(tagConfig, allowNamespace)
		else:
			tagConfig = this.createTagConfig(
				Token.createToken(typeId, TOKEN_WORD),
				Token.createToken("\"\"", TOKEN_STRING), False)

		tagConfig.weight = assignWight
		return tagConfig


	createTagConfig(id, data, present:
		var idString = id.toString()
		var tagConfig = this.tagMap[idString]
		if tagConfig:
			this.error(id, "Duplicate tag identifiers '" + idString + "'.")
		else:
			tagConfig = {
				weight: 0,
				id: id,
				data: data,
				present: present,
				namespace: None,
				tagName: None,
				options: [],
				emitResult: None,
				emitName: None,
			}
			this.tagList.append(tagConfig)
			this.tagMap[idString] = tagConfig
			this.tagMapSize++

		return tagConfig


	processTagConfigs(declaration:
		var tag = declaration.tag
		if declaration.commentTag:
			tag = declaration.commentTag


		if not tag:
			return


		var lexer = new Lexer(
			this.source,
			this.line,
			golangBinaryTagConfig,
			tag.position + 1, # Skip binary prefix  '`'
			tag.length - 2)

		for ; ;:
			var id = lexer.getToken()
			if id.isNull():
				return


			if not id.isAnyWord():
				this.error(id, "Tag identifier expected, found " + id.toInfoString() + ".")
				break


			var token = lexer.getToken()
			if not token.isPunct(":"):
				this.error(token, "Separator ':' expected ater tag '" + id.toString() +
					"', found " + token.toInfoString() + ".")
				break


			var data = lexer.getToken()
			if not data.isString():
				this.error(data, "Configuration string expected for '" + id.toString() +
					"', found " + data.toInfoString() + ".")
				break


			this.createTagConfig(id, data, True)



	processMarshalConfig(tagConfig, allowNamespace:
		var lexer = new Lexer(
			this.source,
			this.line,
			golangXmlTagConfig,
			tagConfig.data.position + 1,
			tagConfig.data.length - 2)

		var token = lexer.getToken()
		if token.isNull():
			this.error(token, "An empty configuration string.")
			return None


		if allowNamespace:
			lexer.whitespaces = True
			var second = lexer.peekToken()
			lexer.whitespaces = False

			if second.isSpace() and token.isAnyWord():
				tagConfig.namespace = token
				lexer.skipToken()
				token = lexer.getToken()



		if token.isAnyWord():
			tagConfig.tagName = token
			token = lexer.getToken()


		if token.isNull():
			return tagConfig


		for ; ;:
			if not token.isPunct(","):
				this.error(token, "Comma separator ',' expected, found " + token.toInfoString() + ".")
				break


			do {
				token = lexer.getToken()
			} while token.isPunct(","))
			if token.isNull():
				return tagConfig


			if not token.isAnyWord():
				this.error(token, "Option identifier expected, found " + token.toInfoString() + ".")
				break


			tagConfig.options.append(token.toString())
			token = lexer.getToken()
			if token.isNull():
				return tagConfig


		return None


	optimizeMarshalConfig(declaration, tagConfig, xmlConfig:
		var self = this

		debug("XMLConfig:" +
			" namespace: " + (tagConfig.namespace ? tagConfig.namespace.toString() : "null") +
			" tagName: " + (tagConfig.tagName ? tagConfig.tagName.toString() : "null") +
			" options: [" + tagConfig.options.join(",") + "]")

		var namespace = tagConfig.namespace ? tagConfig.namespace.toString() : None
		var newNamespace = namespace
		var tagName = tagConfig.tagName ? tagConfig.tagName.toString() : None
		var newTagName = tagName

		var newOptionsChanged = False
		var newOptions = [...tagConfig.options]
		var tagPoint = tagConfig.tagName ? tagConfig.tagName : tagConfig.id

		var shortNs = None
		debug("Processing namespace '" + namespace + "'.")
		if namespace:
			shortNs = reverseOnvifNamespaces[namespace]
			debug("Short namespace '" + shortNs + "'.")
			if not shortNs:
				if unknonLongNs.indexOf(namespace) < 0:
					unknonLongNs.append(namespace)
					this.warn(tagConfig.namespace, "Can not find short NS for '" + namespace + "'.")




		def applyShortNs():
			if shortNs and optimizationOptions.transformNs:
				newNamespace = None
				newTagName = shortNs + ":" + pureTagName
				self.info(tagPoint, "Short namespace '" + shortNs + "' applied to '" + pureTagName + "'.")



		const declName = declaration.name.toString()
		var pureTagName = declName

		//
		# Process XML namespaces.
		//

		if tagName:
			var pureTagNs = ""
			pureTagName = tagName
			var separator = tagName.indexOf(":")
			if separator >= 0:
				pureTagNs = tagName.substr(0, separator)
				pureTagName = tagName.substr(separator + 1)
				if pureTagName is "":
					this.warn(tagPoint, "An empty tag name after NS.")
					pureTagName = declName



			if pureTagName is "-":
				newTagName = "-"
				if optimizationOptions.transformNs and newNamespace is not None:
					newNamespace = None
					this.info(tagPoint, "Removing unnecessary namespace '" + newNamespace + "'.")

			elif pureTagNs.length is not 0:
				if not directOnvifNamespaces[pureTagNs]:
					if not specialNamespaces[pureTagNs]:
						if unknonShortNs.indexOf(pureTagNs) < 0:
							unknonShortNs.append(pureTagNs)
							this.warn(tagPoint, "Unknown short namespace in tag '" + pureTagNs + "'.")

					elif pureTagNs is "xmlns":
						if not directOnvifNamespaces[pureTagName]:
							if unknonXmlnsNs.indexOf(pureTagName) < 0:
								unknonXmlnsNs.append(pureTagName)
								this.warn(tagPoint, "Short XMLNS namespace '" + pureTagName + "' is not registered.")




				if optimizationOptions.transformNs and newNamespace is not None:
					newNamespace = None
					this.info(tagPoint, "Removing unnecessary namespace '" + newNamespace + "'.")

			elif namespace:
				applyShortNs()
			elif pureTagName is declName:
				if optimizationOptions.omitTagNames:
					newTagName = None
					this.info(tagPoint, "Tag name '" + pureTagName + "' matches declaration and can be removed.")


		else:
			if namespace:
				applyShortNs()


		const emitName = pureTagName
		tagConfig.emitName = emitName

		//
		# Additional JSON postprocessing.
		//

		if xmlConfig:
			var tagPoint = tagConfig.present ?
				(tagConfig.tagName ? tagConfig.tagName : tagConfig.id) :
				(xmlConfig.tagName ? xmlConfig.tagName : xmlConfig.id)
			var declType = declaration.type.toString()
			var internalType = False
			if declType is "xml.Name") {
				internalType = True
			}

			var omitted = False
			if optimizationOptions.omitXmlInternals:
				if internalType:
					newTagName = "-"
					newNamespace = None
					newOptions = []
					newOptionsChanged = True
					omitted = True
					this.info(declaration.type, "JSON internal XML/SOAP implementation type '" + declType + "' has been omitted.")



			if not omitted:
				# Derrive config from XML/SOAP.
				if not internalType and xmlConfig.present:
					var xmlEmitName = xmlConfig.emitName
					if optimizationOptions.derriveJsonKeys and xmlEmitName is not emitName:
						if optimizationOptions.overrideJsonKeysor not tagName:
							newTagName = xmlEmitName
							var prefix = tagName ? "" : "Imaginary "
							if xmlEmitName is "-":
								this.info(tagPoint, prefix + "JSON key is hidden by XML/SOAP settings.")
							else:
								if 1or tagName is not newTagName:
									this.info(tagPoint, prefix + "JSON key '" + emitName + "' is overriden by XML/SOAP tag '" + xmlEmitName + "'.")


						 else
							if xmlEmitName is "-":
								this.warn(tagPoint, "Visible JSON key '" + tagName + " is hidden by XML/SOAP settings.")
							elif tagName is "-":
								this.warn(tagPoint, "Visible XML/SOAP tag '" + xmlEmitName + " is hidden by JSON settings.")
							else:
								this.warn(tagPoint, "Specified JSON key '" + tagName + "' differs from XML/SOAP tag '" + xmlEmitName + "'.")






			if optimizationOptions.derriveOmitempty and xmlConfig.options.indexOf("omitempty") >= 0 &&
				newOptions.indexOf("omitempty") < 0:
				newOptions.append("omitempty")
				newOptionsChanged = True
				this.info(tagPoint, "JSON 'omitempty' flag is derrived from XML/JSOAP config.")


			# Omit empty pointed types.
			var xmlState = this.tagMap["xml"]
			var jsonState = this.tagMap["json"]
			if (xmlState and xmlState.present)or (jsonState and jsonState.present):
				if (declaration.isPointer and optimizationOptions.omitPointerTypes) ||
					(declaration.isArray and optimizationOptions.omitArrayTypes):
					if newOptions.indexOf("omitempty") < 0:
						newOptions.append("omitempty")
						newOptionsChanged = True
						this.info(tagPoint, "Added JSON 'omitempty' flag for pointed/array type.")





		//
		# Finalize changes.
		//

		if optimizationOptions.sortOptionsor newOptionsChanged:
			var seen = {}
			newOptions = newOptions.filter(def (item):
				return seen.hasOwnProperty(item) ? False : (seen[item] = True)
			)
			newOptions.sort()

		newOptionsChanged = not (newOptions.length is tagConfig.options.length &&
			newOptions.every((element, index) => element is tagConfig.options[index]))

		if optimizationOptions.omitTagNames and newTagName is declName:
			newTagName = None
			this.info(tagPoint, "Tag name '" + pureTagName + "' matches declaration and can be removed.")


		if newOptionsChangedor namespace is not newNamespaceor tagName is not newTagName:
			var emitResult = ""
			if newNamespace:
				emitResult = newNamespace + " "
				if not newTagName:
					newTagName = declName



			if newTagName:
				emitResult += newTagName


			if newOptions.length is not 0:
				newOptions.sort()
				emitResult += "," + newOptions.join(",")


			emitResult = "\"" + emitResult + "\""
			tagConfig.emitResult = emitResult
			debug("Optimized from: " + tagConfig.id.toString() + ":" + tagConfig.data.toString())
			debug("Optimized   to: " + tagConfig.id.toString() + ":" + emitResult)


}

class FileParser {
	constructor(fileName, log:
		this.fileName = fileName
		this.log = log
		this.structDefinition = None

	parse(readonlyMode:
		var textModified = False
		var text = fs.readFileSync(this.fileName).toString().split("\n")
		for var index = 0; index < text.length; index++:
			var line = text[index]
			var tabLine = line.replace(TAB_REGEXP, TAB_REPLACE)

			var parser = new LineParser(tabLine, index, this, False)
			parser.parse()
			if parser.newSource:
				parser = new LineParser(line, index, this, True)
				parser.parse()
				if not parser.newSource:
					parser.silent = False
					parser.error("Fatal. Failed to parse source line.")
				else:
					textModified = True
					text[index] = parser.newSource




		if textModified and not readonlyMode:
			var backupName = this.fileName + backupFilePostfix
			if CREATE_BACKUP and not fs.existsSync(backupName):
				try:
					fs.copyFileSync(this.fileName, backupName)
				except Exception as e:
					this.log.error("Unable to creatre backup file '" + backupName + "': " + e + ".")
					return



			var outputName = this.fileName + outputFilePostfix
			var textData = text.join("\n")
			try:
				var fd = fs.openSync(outputName, 'w', 0o666)
				fs.writeSync(fd, textData)
				fs.closeSync(fd)
			except Exception as e:
				this.log.error("Unable to write file '" + outputName + "': " + e + ".")
				return


			try:
				child_process.exec("gofmt -w " + outputName)
			except Exception as e:
				this.log.error("Unable to execute 'gofmt' on file '" + outputName + "': " + e + ".")
				return



}

class LogFile {
	constructor(fileName:
		this.fileName = fileName
		this.fd = fs.openSync(fileName, 'w', 0o666)
		this.infoCount = 0
		this.warnCount = 0
		this.errorCount = 0


	write(:
		for var index = 0; index < arguments.length; index++:
			var message = arguments[index]
			console.info(message)
			fs.writeSync(this.fd, arguments[index])
			fs.writeSync(this.fd, "\n")



	info(message:
		this.infoCount++
		this.write("INFO: " + message)


	warn(message:
		this.write("WARNING: " + message)


	error(message:
		this.errorCount++
		this.write("ERROR: " + message)

}

def getAllFiles(dirPath, arrayOfFiles):
	arrayOfFiles = arrayOfFilesor []
	files = fs.readdirSync(dirPath)
	files.forEach(def(file):
	  if fs.statSync(dirPath + "/" + file).isDirectory():
		arrayOfFiles = getAllFiles(dirPath + "/" + file, arrayOfFiles)
	  else:
		arrayOfFiles.append(path.join(dirPath, "/", file))

	)

	return arrayOfFiles


def execute():
	filelist = getAllFiles(".")
	var filteredFiles = filelist.filter(def(file){
		return file.endsWith('.go')
	})

	var log = new LogFile(logFileName)
	log.write("Started " + new Date().toISOString())

	for var index = 0; index < filteredFiles.length; index++):
		var fileName = filteredFiles[index]
		var file = new FileParser(fileName, log)
		file.parse(False)



execute()
