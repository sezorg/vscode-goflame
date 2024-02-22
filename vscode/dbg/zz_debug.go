package dbg

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"reflect"
	"regexp"
	"runtime"
	"sort"
	"strconv"
	"strings"
	"syscall"
	"unsafe"
)

type IErrorInterface interface {
	Error() string
}
type IStringInterface interface {
	String() string
}

var (
	breakOnError = false
	runTests     = true
)

func RunTest(test func()) int {
	if runTests {
		test()
	}
	return 0
}

func TraceLine() {
	pc := make([]uintptr, 10) // at least 1 entry needed
	runtime.Callers(2, pc)
	f := runtime.FuncForPC(pc[0])
	file, line := f.FileLine(pc[0])
	fmt.Printf("%s:%d %s\n", file, line, f.Name())
}

func BreakOnError(value bool) {
	breakOnError = value
}

func Err(err error) error {
	if err != nil {
		Debugln(err)
	}
	return err
}

func Assert(condition bool) {
	if !condition {
		printDebug(3, "Assertion failed")
		log.Panic("Assertion failed")
	}
}

var (
	TestSimpleOk   = true
	TestToRun      = ""
	TestExitOnFail = true
	testExecuted   = []string{}
)

func Test(uid string, method func() error, expect string) {
	if stringListContains(testExecuted, uid) {
		printDebug(3, uid, "[FAIL]: tester: test already executed:", uid)
		if TestExitOnFail {
			os.Exit(0)
		}
	}
	if TestToRun != "" && TestToRun != uid {
		return
	}
	err := method()
	if expect == "" {
		if err == nil {
			if TestSimpleOk {
				printDebug(3, uid, "[OK]")
			} else {
				printDebug(3, uid, "[OK]: err == nil")
			}
		} else {
			printDebug(3, uid, "[FAIL]: expect: err == nil")
			printDebug(3, uid, "[FAIL]: result:", err)
			if TestExitOnFail {
				os.Exit(0)
			}
		}
	} else if err != nil {
		if strings.Index(err.Error(), expect) >= 0 {
			if TestSimpleOk {
				printDebug(3, uid, "[OK]")
			} else {
				printDebug(3, uid, "[OK]:", err)
			}
		} else {
			printDebug(3, uid, "[FAIL]: expect:", expect)
			printDebug(3, uid, "[FAIL]: result:", err)
			if TestExitOnFail {
				os.Exit(0)
			}
		}
	} else {
		printDebug(3, uid, "[FAIL]: expect:", expect)
		printDebug(3, uid, "[FAIL]: result: err == nil")
		if TestExitOnFail {
			os.Exit(0)
		}
	}
}

func stringListContains(list []string, value string) bool {
	for _, item := range list {
		if item == value {
			return true
		}
	}
	return false
}

func Ln(values ...interface{}) {
	printDebug(3, values...)
}

func Debugln(values ...interface{}) {
	printDebug(3, values...)
}

func printDebug(callDepth int, values ...interface{}) {
	raiseSigtrap := false
	log.SetFlags(log.LstdFlags | log.Lshortfile)
	for index, value := range values {
		if errorToString, ok := value.(IErrorInterface); ok {
			if value != nil {
				raiseSigtrap = breakOnError
				values[index] = "error: " + errorToString.Error()
			} else {
				values[index] = "error(nil)"
			}
			continue
		}
		if value == nil {
			values[index] = "nil"
			continue
		}
		if refType, ok := value.(reflect.Type); ok {
			values[index] = ReflectTypeToString(refType)
			continue
		}
		if httpReq, ok := value.(*http.Request); ok {
			values[index] = formatRequest(httpReq)
			continue
		}
		if someToString, ok := value.(IStringInterface); ok {
			values[index] = someToString.String()
			continue
		}
		valueType := reflect.TypeOf(value)
		valueKind := valueType.Kind()
		for valueKind == reflect.Ptr {
			valueType = valueType.Elem()
			valueKind = valueType.Kind()
		}
		switch valueKind {
		case reflect.Struct, reflect.Slice, reflect.Map:
			values[index] = Sdump(value)
		}
	}
	values = append([]interface{}{"Debug:"}, values...)
	text := fmt.Sprintln(values...)
	log.Output(callDepth, text)

	//journal.Print(journal.PriDebug, "%v", text)

	if raiseSigtrap {
		sep := "------------------------------------------------------------------------"
		log.Output(2, "SIGTRAP")
		log.Output(2, sep)
		log.Output(2, sep)
		log.Output(2, sep)
		exec.Command("kill", "-SIGTRAP", strconv.Itoa(syscall.Getpid())).Run()
		panic("SIGTRAP")
	}

}

func PrettyPrint(i interface{}) string {
	s, _ := json.MarshalIndent(i, "", "\t")
	return string(s)
}

func ReflectTypeToString(source reflect.Type) string {
	var typeKind, typeName string
	kind := source.Kind()
	switch kind {
	case reflect.Slice:
		return "[]" + ReflectTypeToString(source.Elem())
	case reflect.Map:
		return "map[" + source.Key().Name() + "]" + ReflectTypeToString(source.Elem())
	case reflect.Ptr:
		return "*" + ReflectTypeToString(source.Elem())
	case reflect.Interface:
		return "interface{" + source.Name() + "}"
	case reflect.Struct:
		return source.Name()
	default:
		typeKind = kind.String()
		typeName = source.Name()
	}
	if typeName != "" {
		typeKind += " " + typeName
	}
	return typeKind
}

func TypeToString(source interface{}) string {
	if source == nil {
		return "nil"
	}
	return ReflectTypeToString(reflect.TypeOf(source))
}

type dumpState struct {
	w                io.Writer
	depth            int
	pointers         map[uintptr]int
	ignoreNextType   bool
	ignoreNextIndent bool
	cs               *ConfigState
}

var (
	uint8Type       = reflect.TypeOf(uint8(0))
	cCharRE         = regexp.MustCompile(`^.*\._Ctype_char$`)
	cUnsignedCharRE = regexp.MustCompile(`^.*\._Ctype_unsignedchar$`)
	cUint8tCharRE   = regexp.MustCompile(`^.*\._Ctype_uint8_t$`)
)

func Sdump(a ...interface{}) string {
	var buf bytes.Buffer
	fdump(&Config, &buf, a...)
	return buf.String()
}

func fdump(cs *ConfigState, w io.Writer, a ...interface{}) {
	for _, arg := range a {
		if arg == nil {
			w.Write(interfaceBytes)
			w.Write(spaceBytes)
			w.Write(nilAngleBytes)
			w.Write(newlineBytes)
			continue
		}
		d := dumpState{w: w, cs: cs}
		d.pointers = make(map[uintptr]int)
		d.dump(reflect.ValueOf(arg))
		d.w.Write(newlineBytes)
	}
}

func (d *dumpState) dump(v reflect.Value) {
	kind := v.Kind()
	if kind == reflect.Invalid {
		d.w.Write(invalidAngleBytes)
		return
	}
	if kind == reflect.Ptr {
		d.indent()
		d.dumpPtr(v)
		return
	}
	if !d.ignoreNextType {
		d.indent()
		d.w.Write(openParenBytes)
		d.w.Write([]byte(v.Type().String()))
		d.w.Write(closeParenBytes)
		d.w.Write(spaceBytes)
	}
	d.ignoreNextType = false
	valueLen, valueCap := 0, 0
	switch v.Kind() {
	case reflect.Array, reflect.Slice, reflect.Chan:
		valueLen, valueCap = v.Len(), v.Cap()
	case reflect.Map, reflect.String:
		valueLen = v.Len()
	}
	if valueLen != 0 || !d.cs.DisableCapacities && valueCap != 0 {
		d.w.Write(openParenBytes)
		if valueLen != 0 {
			d.w.Write(lenEqualsBytes)
			printInt(d.w, int64(valueLen), 10)
		}
		if !d.cs.DisableCapacities && valueCap != 0 {
			if valueLen != 0 {
				d.w.Write(spaceBytes)
			}
			d.w.Write(capEqualsBytes)
			printInt(d.w, int64(valueCap), 10)
		}
		d.w.Write(closeParenBytes)
		d.w.Write(spaceBytes)
	}
	if !d.cs.DisableMethods {
		if (kind != reflect.Invalid) && (kind != reflect.Interface) {
			if handled := handleMethods(d.cs, d.w, v); handled {
				return
			}
		}
	}
	switch kind {
	case reflect.Invalid:
	case reflect.Bool:
		printBool(d.w, v.Bool())
	case reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64, reflect.Int:
		printInt(d.w, v.Int(), 10)
	case reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uint:
		printUint(d.w, v.Uint(), 10)
	case reflect.Float32:
		printFloat(d.w, v.Float(), 32)
	case reflect.Float64:
		printFloat(d.w, v.Float(), 64)
	case reflect.Complex64:
		printComplex(d.w, v.Complex(), 32)
	case reflect.Complex128:
		printComplex(d.w, v.Complex(), 64)
	case reflect.Slice:
		if v.IsNil() {
			d.w.Write(nilAngleBytes)
			break
		}
		fallthrough
	case reflect.Array:
		d.w.Write(openBraceNewlineBytes)
		d.depth++
		if (d.cs.MaxDepth != 0) && (d.depth > d.cs.MaxDepth) {
			d.indent()
			d.w.Write(maxNewlineBytes)
		} else {
			d.dumpSlice(v)
		}
		d.depth--
		d.indent()
		d.w.Write(closeBraceBytes)
	case reflect.String:
		d.w.Write([]byte(strconv.Quote(v.String())))
	case reflect.Interface:
		if v.IsNil() {
			d.w.Write(nilAngleBytes)
		}
	case reflect.Ptr:
	case reflect.Map:
		if v.IsNil() {
			d.w.Write(nilAngleBytes)
			break
		}
		d.w.Write(openBraceNewlineBytes)
		d.depth++
		if (d.cs.MaxDepth != 0) && (d.depth > d.cs.MaxDepth) {
			d.indent()
			d.w.Write(maxNewlineBytes)
		} else {
			numEntries := v.Len()
			keys := v.MapKeys()
			if d.cs.SortKeys {
				sortValues(keys, d.cs)
			}
			for i, key := range keys {
				d.dump(d.unpackValue(key))
				d.w.Write(colonSpaceBytes)
				d.ignoreNextIndent = true
				d.dump(d.unpackValue(v.MapIndex(key)))
				if i < (numEntries - 1) {
					d.w.Write(commaNewlineBytes)
				} else {
					d.w.Write(newlineBytes)
				}
			}
		}
		d.depth--
		d.indent()
		d.w.Write(closeBraceBytes)
	case reflect.Struct:
		d.w.Write(openBraceNewlineBytes)
		d.depth++
		if (d.cs.MaxDepth != 0) && (d.depth > d.cs.MaxDepth) {
			d.indent()
			d.w.Write(maxNewlineBytes)
		} else {
			vt := v.Type()
			numFields := v.NumField()
			for i := 0; i < numFields; i++ {
				d.indent()
				vtf := vt.Field(i)
				d.w.Write([]byte(vtf.Name))
				d.w.Write(colonSpaceBytes)
				d.ignoreNextIndent = true
				d.dump(d.unpackValue(v.Field(i)))
				if i < (numFields - 1) {
					d.w.Write(commaNewlineBytes)
				} else {
					d.w.Write(newlineBytes)
				}
			}
		}
		d.depth--
		d.indent()
		d.w.Write(closeBraceBytes)
	case reflect.Uintptr:
		printHexPtr(d.w, uintptr(v.Uint()))
	case reflect.UnsafePointer, reflect.Chan, reflect.Func:
		printHexPtr(d.w, v.Pointer())
	default:
		if v.CanInterface() {
			fmt.Fprintf(d.w, "%v", v.Interface())
		} else {
			fmt.Fprintf(d.w, "%v", v.String())
		}
	}
}

func (d *dumpState) indent() {
	if d.ignoreNextIndent {
		d.ignoreNextIndent = false
		return
	}
	d.w.Write(bytes.Repeat([]byte(d.cs.Indent), d.depth))
}

func (d *dumpState) unpackValue(v reflect.Value) reflect.Value {
	if v.Kind() == reflect.Interface && !v.IsNil() {
		v = v.Elem()
	}
	return v
}

func (d *dumpState) dumpPtr(v reflect.Value) {
	for k, depth := range d.pointers {
		if depth >= d.depth {
			delete(d.pointers, k)
		}
	}
	pointerChain := make([]uintptr, 0)
	nilFound := false
	cycleFound := false
	indirects := 0
	ve := v
	for ve.Kind() == reflect.Ptr {
		if ve.IsNil() {
			nilFound = true
			break
		}
		indirects++
		addr := ve.Pointer()
		pointerChain = append(pointerChain, addr)
		if pd, ok := d.pointers[addr]; ok && pd < d.depth {
			cycleFound = true
			indirects--
			break
		}
		d.pointers[addr] = d.depth
		ve = ve.Elem()
		if ve.Kind() == reflect.Interface {
			if ve.IsNil() {
				nilFound = true
				break
			}
			ve = ve.Elem()
		}
	}
	d.w.Write(openParenBytes)
	d.w.Write(bytes.Repeat(asteriskBytes, indirects))
	d.w.Write([]byte(ve.Type().String()))
	d.w.Write(closeParenBytes)
	if !d.cs.DisablePointerAddresses && len(pointerChain) > 0 {
		d.w.Write(openParenBytes)
		for i, addr := range pointerChain {
			if i > 0 {
				d.w.Write(pointerChainBytes)
			}
			printHexPtr(d.w, addr)
		}
		d.w.Write(closeParenBytes)
	}
	d.w.Write(openParenBytes)
	switch {
	case nilFound:
		d.w.Write(nilAngleBytes)
	case cycleFound:
		d.w.Write(circularBytes)
	default:
		d.ignoreNextType = true
		d.dump(ve)
	}
	d.w.Write(closeParenBytes)
}

func (d *dumpState) dumpSlice(v reflect.Value) {
	var buf []uint8
	doConvert := false
	doHexDump := false
	numEntries := v.Len()
	if numEntries > 0 {
		vt := v.Index(0).Type()
		vts := vt.String()
		switch {
		case cCharRE.MatchString(vts):
			fallthrough
		case cUnsignedCharRE.MatchString(vts):
			fallthrough
		case cUint8tCharRE.MatchString(vts):
			doConvert = true
		case vt.Kind() == reflect.Uint8:
			vs := v
			if !vs.CanInterface() || !vs.CanAddr() {
				vs = unsafeReflectValue(vs)
			}
			if !UnsafeDisabled {
				vs = vs.Slice(0, numEntries)
				iface := vs.Interface()
				if slice, ok := iface.([]uint8); ok {
					buf = slice
					doHexDump = true
					break
				}
			}
			doConvert = true
		}
		if doConvert && vt.ConvertibleTo(uint8Type) {
			buf = make([]uint8, numEntries)
			for i := 0; i < numEntries; i++ {
				vv := v.Index(i)
				buf[i] = uint8(vv.Convert(uint8Type).Uint())
			}
			doHexDump = true
		}
	}
	if doHexDump {
		indent := strings.Repeat(d.cs.Indent, d.depth)
		str := indent + hex.Dump(buf)
		str = strings.Replace(str, "\n", "\n"+indent, -1)
		str = strings.TrimRight(str, d.cs.Indent)
		d.w.Write([]byte(str))
		return
	}
	for i := 0; i < numEntries; i++ {
		d.dump(d.unpackValue(v.Index(i)))
		if i < (numEntries - 1) {
			d.w.Write(commaNewlineBytes)
		} else {
			d.w.Write(newlineBytes)
		}
	}
}

type ConfigState struct {
	Indent                  string
	MaxDepth                int
	DisableMethods          bool
	DisablePointerMethods   bool
	DisablePointerAddresses bool
	DisableCapacities       bool
	ContinueOnMethod        bool
	SortKeys                bool
	SpewKeys                bool
}

var Config = ConfigState{Indent: " "}

type formatState struct {
	value          interface{}
	fs             fmt.State
	depth          int
	pointers       map[uintptr]int
	ignoreNextType bool
	cs             *ConfigState
}

func newFormatter(cs *ConfigState, v interface{}) fmt.Formatter {
	fs := &formatState{value: v, cs: cs}
	fs.pointers = make(map[uintptr]int)
	return fs
}

func NewFormatter(v interface{}) fmt.Formatter {
	return newFormatter(&Config, v)
}

const supportedFlags = "0-+# "

func (f *formatState) buildDefaultFormat() (format string) {
	buf := bytes.NewBuffer(percentBytes)
	for _, flag := range supportedFlags {
		if f.fs.Flag(int(flag)) {
			buf.WriteRune(flag)
		}
	}
	buf.WriteRune('v')
	format = buf.String()
	return format
}

func (f *formatState) constructOrigFormat(verb rune) (format string) {
	buf := bytes.NewBuffer(percentBytes)
	for _, flag := range supportedFlags {
		if f.fs.Flag(int(flag)) {
			buf.WriteRune(flag)
		}
	}
	if width, ok := f.fs.Width(); ok {
		buf.WriteString(strconv.Itoa(width))
	}
	if precision, ok := f.fs.Precision(); ok {
		buf.Write(precisionBytes)
		buf.WriteString(strconv.Itoa(precision))
	}
	buf.WriteRune(verb)
	format = buf.String()
	return format
}

func (f *formatState) unpackValue(v reflect.Value) reflect.Value {
	if v.Kind() == reflect.Interface {
		f.ignoreNextType = false
		if !v.IsNil() {
			v = v.Elem()
		}
	}
	return v
}

func (f *formatState) formatPtr(v reflect.Value) {
	showTypes := f.fs.Flag('#')
	if v.IsNil() && (!showTypes || f.ignoreNextType) {
		f.fs.Write(nilAngleBytes)
		return
	}
	for k, depth := range f.pointers {
		if depth >= f.depth {
			delete(f.pointers, k)
		}
	}
	pointerChain := make([]uintptr, 0)
	nilFound := false
	cycleFound := false
	indirects := 0
	ve := v
	for ve.Kind() == reflect.Ptr {
		if ve.IsNil() {
			nilFound = true
			break
		}
		indirects++
		addr := ve.Pointer()
		pointerChain = append(pointerChain, addr)
		if pd, ok := f.pointers[addr]; ok && pd < f.depth {
			cycleFound = true
			indirects--
			break
		}
		f.pointers[addr] = f.depth
		ve = ve.Elem()
		if ve.Kind() == reflect.Interface {
			if ve.IsNil() {
				nilFound = true
				break
			}
			ve = ve.Elem()
		}
	}
	if showTypes && !f.ignoreNextType {
		f.fs.Write(openParenBytes)
		f.fs.Write(bytes.Repeat(asteriskBytes, indirects))
		f.fs.Write([]byte(ve.Type().String()))
		f.fs.Write(closeParenBytes)
	} else {
		if nilFound || cycleFound {
			indirects += strings.Count(ve.Type().String(), "*")
		}
		f.fs.Write(openAngleBytes)
		f.fs.Write([]byte(strings.Repeat("*", indirects)))
		f.fs.Write(closeAngleBytes)
	}
	if f.fs.Flag('+') && (len(pointerChain) > 0) {
		f.fs.Write(openParenBytes)
		for i, addr := range pointerChain {
			if i > 0 {
				f.fs.Write(pointerChainBytes)
			}
			printHexPtr(f.fs, addr)
		}
		f.fs.Write(closeParenBytes)
	}
	switch {
	case nilFound:
		f.fs.Write(nilAngleBytes)
	case cycleFound:
		f.fs.Write(circularShortBytes)
	default:
		f.ignoreNextType = true
		f.format(ve)
	}
}

func (f *formatState) format(v reflect.Value) {
	kind := v.Kind()
	if kind == reflect.Invalid {
		f.fs.Write(invalidAngleBytes)
		return
	}
	if kind == reflect.Ptr {
		f.formatPtr(v)
		return
	}
	if !f.ignoreNextType && f.fs.Flag('#') {
		f.fs.Write(openParenBytes)
		f.fs.Write([]byte(v.Type().String()))
		f.fs.Write(closeParenBytes)
	}
	f.ignoreNextType = false
	if !f.cs.DisableMethods {
		if (kind != reflect.Invalid) && (kind != reflect.Interface) {
			if handled := handleMethods(f.cs, f.fs, v); handled {
				return
			}
		}
	}
	switch kind {
	case reflect.Invalid:
	case reflect.Bool:
		printBool(f.fs, v.Bool())
	case reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64, reflect.Int:
		printInt(f.fs, v.Int(), 10)
	case reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uint:
		printUint(f.fs, v.Uint(), 10)
	case reflect.Float32:
		printFloat(f.fs, v.Float(), 32)
	case reflect.Float64:
		printFloat(f.fs, v.Float(), 64)
	case reflect.Complex64:
		printComplex(f.fs, v.Complex(), 32)
	case reflect.Complex128:
		printComplex(f.fs, v.Complex(), 64)
	case reflect.Slice:
		if v.IsNil() {
			f.fs.Write(nilAngleBytes)
			break
		}
		fallthrough
	case reflect.Array:
		f.fs.Write(openBracketBytes)
		f.depth++
		if (f.cs.MaxDepth != 0) && (f.depth > f.cs.MaxDepth) {
			f.fs.Write(maxShortBytes)
		} else {
			numEntries := v.Len()
			for i := 0; i < numEntries; i++ {
				if i > 0 {
					f.fs.Write(spaceBytes)
				}
				f.ignoreNextType = true
				f.format(f.unpackValue(v.Index(i)))
			}
		}
		f.depth--
		f.fs.Write(closeBracketBytes)
	case reflect.String:
		f.fs.Write([]byte(v.String()))
	case reflect.Interface:
		if v.IsNil() {
			f.fs.Write(nilAngleBytes)
		}
	case reflect.Ptr:
	case reflect.Map:
		if v.IsNil() {
			f.fs.Write(nilAngleBytes)
			break
		}
		f.fs.Write(openMapBytes)
		f.depth++
		if (f.cs.MaxDepth != 0) && (f.depth > f.cs.MaxDepth) {
			f.fs.Write(maxShortBytes)
		} else {
			keys := v.MapKeys()
			if f.cs.SortKeys {
				sortValues(keys, f.cs)
			}
			for i, key := range keys {
				if i > 0 {
					f.fs.Write(spaceBytes)
				}
				f.ignoreNextType = true
				f.format(f.unpackValue(key))
				f.fs.Write(colonBytes)
				f.ignoreNextType = true
				f.format(f.unpackValue(v.MapIndex(key)))
			}
		}
		f.depth--
		f.fs.Write(closeMapBytes)
	case reflect.Struct:
		numFields := v.NumField()
		f.fs.Write(openBraceBytes)
		f.depth++
		if (f.cs.MaxDepth != 0) && (f.depth > f.cs.MaxDepth) {
			f.fs.Write(maxShortBytes)
		} else {
			vt := v.Type()
			for i := 0; i < numFields; i++ {
				if i > 0 {
					f.fs.Write(spaceBytes)
				}
				vtf := vt.Field(i)
				if f.fs.Flag('+') || f.fs.Flag('#') {
					f.fs.Write([]byte(vtf.Name))
					f.fs.Write(colonBytes)
				}
				f.format(f.unpackValue(v.Field(i)))
			}
		}
		f.depth--
		f.fs.Write(closeBraceBytes)
	case reflect.Uintptr:
		printHexPtr(f.fs, uintptr(v.Uint()))
	case reflect.UnsafePointer, reflect.Chan, reflect.Func:
		printHexPtr(f.fs, v.Pointer())
	default:
		format := f.buildDefaultFormat()
		if v.CanInterface() {
			fmt.Fprintf(f.fs, format, v.Interface())
		} else {
			fmt.Fprintf(f.fs, format, v.String())
		}
	}
}

func (f *formatState) Format(fs fmt.State, verb rune) {
	f.fs = fs
	if verb != 'v' {
		format := f.constructOrigFormat(verb)
		fmt.Fprintf(fs, format, f.value)
		return
	}
	if f.value == nil {
		if fs.Flag('#') {
			fs.Write(interfaceBytes)
		}
		fs.Write(nilAngleBytes)
		return
	}
	f.format(reflect.ValueOf(f.value))
}

const (
	UnsafeDisabled = false
	ptrSize        = unsafe.Sizeof((*byte)(nil))
)

type flag uintptr

var (
	flagRO   flag
	flagAddr flag
)

var okFlags = []struct {
	ro, addr flag
}{{
	ro:   1 << 5,
	addr: 1 << 7,
}, {
	ro:   1<<5 | 1<<6,
	addr: 1 << 8,
}}
var flagValOffset = func() uintptr {
	field, ok := reflect.TypeOf(reflect.Value{}).FieldByName("flag")
	if !ok {
		panic("reflect.Value has no flag field")
	}
	return field.Offset
}()

func flagField(v *reflect.Value) *flag {
	return (*flag)(unsafe.Pointer(uintptr(unsafe.Pointer(v)) + flagValOffset))
}

func unsafeReflectValue(v reflect.Value) reflect.Value {
	if !v.IsValid() || (v.CanInterface() && v.CanAddr()) {
		return v
	}
	flagFieldPtr := flagField(&v)
	*flagFieldPtr &^= flagRO
	*flagFieldPtr |= flagAddr
	return v
}

func init() {
	field, ok := reflect.TypeOf(reflect.Value{}).FieldByName("flag")
	if !ok {
		panic("reflect.Value has no flag field")
	}
	if field.Type.Kind() != reflect.TypeOf(flag(0)).Kind() {
		panic("reflect.Value flag field has changed kind")
	}
	type t0 int
	var t struct {
		A t0
		t0
		a t0
	}
	vA := reflect.ValueOf(t).FieldByName("A")
	va := reflect.ValueOf(t).FieldByName("a")
	vt0 := reflect.ValueOf(t).FieldByName("t0")
	flagPublic := *flagField(&vA)
	flagWithRO := *flagField(&va) | *flagField(&vt0)
	flagRO = flagPublic ^ flagWithRO
	vPtrA := reflect.ValueOf(&t).Elem().FieldByName("A")
	flagNoPtr := *flagField(&vA)
	flagPtr := *flagField(&vPtrA)
	flagAddr = flagNoPtr ^ flagPtr
	for _, f := range okFlags {
		if flagRO == f.ro && flagAddr == f.addr {
			return
		}
	}
	panic("reflect.Value read-only flag has changed semantics")
}

var (
	panicBytes            = []byte("(PANIC=")
	plusBytes             = []byte("+")
	iBytes                = []byte("i")
	trueBytes             = []byte("true")
	falseBytes            = []byte("false")
	interfaceBytes        = []byte("(interface {})")
	commaNewlineBytes     = []byte(",\n")
	newlineBytes          = []byte("\n")
	openBraceBytes        = []byte("{")
	openBraceNewlineBytes = []byte("{\n")
	closeBraceBytes       = []byte("}")
	asteriskBytes         = []byte("*")
	colonBytes            = []byte(":")
	colonSpaceBytes       = []byte(": ")
	openParenBytes        = []byte("(")
	closeParenBytes       = []byte(")")
	spaceBytes            = []byte(" ")
	pointerChainBytes     = []byte("->")
	nilAngleBytes         = []byte("<nil>")
	maxNewlineBytes       = []byte("<max depth reached>\n")
	maxShortBytes         = []byte("<max>")
	circularBytes         = []byte("<already shown>")
	circularShortBytes    = []byte("<shown>")
	invalidAngleBytes     = []byte("<invalid>")
	openBracketBytes      = []byte("[")
	closeBracketBytes     = []byte("]")
	percentBytes          = []byte("%")
	precisionBytes        = []byte(".")
	openAngleBytes        = []byte("<")
	closeAngleBytes       = []byte(">")
	openMapBytes          = []byte("map[")
	closeMapBytes         = []byte("]")
	lenEqualsBytes        = []byte("len=")
	capEqualsBytes        = []byte("cap=")
)
var hexDigits = "0123456789abcdef"

func catchPanic(w io.Writer, v reflect.Value) {
	if err := recover(); err != nil {
		w.Write(panicBytes)
		fmt.Fprintf(w, "%v", err)
		w.Write(closeParenBytes)
	}
}

func handleMethods(cs *ConfigState, w io.Writer, v reflect.Value) (handled bool) {
	if !v.CanInterface() {
		if UnsafeDisabled {
			return false
		}
		v = unsafeReflectValue(v)
	}
	if !cs.DisablePointerMethods && !UnsafeDisabled && !v.CanAddr() {
		v = unsafeReflectValue(v)
	}
	if v.CanAddr() {
		v = v.Addr()
	}
	switch iface := v.Interface().(type) {
	case error:
		defer catchPanic(w, v)
		if cs.ContinueOnMethod {
			w.Write(openParenBytes)
			w.Write([]byte(iface.Error()))
			w.Write(closeParenBytes)
			w.Write(spaceBytes)
			return false
		}
		w.Write([]byte(iface.Error()))
		return true
	case fmt.Stringer:
		defer catchPanic(w, v)
		if cs.ContinueOnMethod {
			w.Write(openParenBytes)
			w.Write([]byte(iface.String()))
			w.Write(closeParenBytes)
			w.Write(spaceBytes)
			return false
		}
		w.Write([]byte(iface.String()))
		return true
	}
	return false
}

func printBool(w io.Writer, val bool) {
	if val {
		w.Write(trueBytes)
	} else {
		w.Write(falseBytes)
	}
}

func printInt(w io.Writer, val int64, base int) {
	w.Write([]byte(strconv.FormatInt(val, base)))
}

func printUint(w io.Writer, val uint64, base int) {
	w.Write([]byte(strconv.FormatUint(val, base)))
}

func printFloat(w io.Writer, val float64, precision int) {
	w.Write([]byte(strconv.FormatFloat(val, 'g', -1, precision)))
}

func printComplex(w io.Writer, c complex128, floatPrecision int) {
	r := real(c)
	w.Write(openParenBytes)
	w.Write([]byte(strconv.FormatFloat(r, 'g', -1, floatPrecision)))
	i := imag(c)
	if i >= 0 {
		w.Write(plusBytes)
	}
	w.Write([]byte(strconv.FormatFloat(i, 'g', -1, floatPrecision)))
	w.Write(iBytes)
	w.Write(closeParenBytes)
}

func printHexPtr(w io.Writer, p uintptr) {
	num := uint64(p)
	if num == 0 {
		w.Write(nilAngleBytes)
		return
	}
	buf := make([]byte, 18)
	base := uint64(16)
	i := len(buf) - 1
	for num >= base {
		buf[i] = hexDigits[num%base]
		num /= base
		i--
	}
	buf[i] = hexDigits[num]
	i--
	buf[i] = 'x'
	i--
	buf[i] = '0'
	buf = buf[i:]
	w.Write(buf)
}

type valuesSorter struct {
	values  []reflect.Value
	strings []string // either nil or same len and values
	cs      *ConfigState
}

func newValuesSorter(values []reflect.Value, cs *ConfigState) sort.Interface {
	vs := &valuesSorter{values: values, cs: cs}
	if canSortSimply(vs.values[0].Kind()) {
		return vs
	}
	if !cs.DisableMethods {
		vs.strings = make([]string, len(values))
		for i := range vs.values {
			b := bytes.Buffer{}
			if !handleMethods(cs, &b, vs.values[i]) {
				vs.strings = nil
				break
			}
			vs.strings[i] = b.String()
		}
	}
	if vs.strings == nil && cs.SpewKeys {
		vs.strings = make([]string, len(values))
		for i := range vs.values {
			vs.strings[i] = Sprintf("%#v", vs.values[i].Interface())
		}
	}
	return vs
}

func canSortSimply(kind reflect.Kind) bool {
	switch kind {
	case reflect.Bool:
		return true
	case reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64, reflect.Int:
		return true
	case reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uint:
		return true
	case reflect.Float32, reflect.Float64:
		return true
	case reflect.String:
		return true
	case reflect.Uintptr:
		return true
	case reflect.Array:
		return true
	}
	return false
}

func (s *valuesSorter) Len() int {
	return len(s.values)
}

func (s *valuesSorter) Swap(i, j int) {
	s.values[i], s.values[j] = s.values[j], s.values[i]
	if s.strings != nil {
		s.strings[i], s.strings[j] = s.strings[j], s.strings[i]
	}
}

func valueSortLess(a, b reflect.Value) bool {
	switch a.Kind() {
	case reflect.Bool:
		return !a.Bool() && b.Bool()
	case reflect.Int8, reflect.Int16, reflect.Int32, reflect.Int64, reflect.Int:
		return a.Int() < b.Int()
	case reflect.Uint8, reflect.Uint16, reflect.Uint32, reflect.Uint64, reflect.Uint:
		return a.Uint() < b.Uint()
	case reflect.Float32, reflect.Float64:
		return a.Float() < b.Float()
	case reflect.String:
		return a.String() < b.String()
	case reflect.Uintptr:
		return a.Uint() < b.Uint()
	case reflect.Array:
		l := a.Len()
		for i := 0; i < l; i++ {
			av := a.Index(i)
			bv := b.Index(i)
			if av.Interface() == bv.Interface() {
				continue
			}
			return valueSortLess(av, bv)
		}
	}
	return a.String() < b.String()
}

func (s *valuesSorter) Less(i, j int) bool {
	if s.strings == nil {
		return valueSortLess(s.values[i], s.values[j])
	}
	return s.strings[i] < s.strings[j]
}

func sortValues(values []reflect.Value, cs *ConfigState) {
	if len(values) == 0 {
		return
	}
	sort.Sort(newValuesSorter(values, cs))
}

func Sprintf(format string, a ...interface{}) string {
	return fmt.Sprintf(format, convertArgs(a)...)
}

func convertArgs(args []interface{}) (formatters []interface{}) {
	formatters = make([]interface{}, len(args))
	for index, arg := range args {
		formatters[index] = NewFormatter(arg)
	}
	return formatters
}

func typeToString(source reflect.Type) string {
	if source == nil {
		return "nil"
	}
	switch source.Kind() { //nolint:exhaustive
	case reflect.Slice, reflect.Array:
		return "[]" + typeToString(source.Elem())
	case reflect.Chan:
		return "chan " + typeToString(source.Elem())
	case reflect.Map:
		return "map[" + typeToString(source.Key()) + "]" + typeToString(source.Elem())
	case reflect.Ptr:
		return "*" + typeToString(source.Elem())
	case reflect.Interface:
		return "interface{}"
	case reflect.Struct:
		return typeName(source)
	}
	return source.Name()
}

func typeName(source reflect.Type) string {
	if source.Kind() == reflect.Struct {
		return "struct " + source.Name()
	}
	return source.Name()
}

func formatRequest(r *http.Request) string {
	request := []string{
		fmt.Sprintf("%v %v %v", r.Method, r.URL, r.Proto),
		fmt.Sprintf("Host: %v", r.Host),
	}
	for name, headers := range r.Header {
		name = strings.ToLower(name)
		for _, h := range headers {
			request = append(request, fmt.Sprintf("%v: %v", name, h))
		}
	}
	if r.Method == "POST" {
		r.ParseForm()
		request = append(request, "\n")
		request = append(request, r.Form.Encode())
	}
	return strings.Join(request, "\n")
}
