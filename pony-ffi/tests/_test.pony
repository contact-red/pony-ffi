use "pony_test"
use "pony_check"
use ".."

actor \nodoc\ Main is TestList
  new create(env: Env) =>
    PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    // CBox
    test(_TestCBoxBasic)
    test(_TestCBoxIntFamily)
    test(_TestWrittenSizePtrIdentity)

    // CBuffer construction & invariants
    test(_TestAllocatedReturnsSize)
    test(_TestInitialWrittenIsZero)
    test(_TestCreateZeroFilled)

    // Write boundaries (example-based)
    test(_TestWriteEmpty)
    test(_TestWriteAtCap)
    test(_TestWriteOverCapReturnsFalse)
    test(_TestWriteOverCapLeavesStateUntouched)
    test(_TestWriteArrayEmpty)
    test(_TestWriteArrayAtCap)
    test(_TestWriteArrayOverCapReturnsFalse)

    // written_size / copy_* boundary semantics
    test(_TestCopyErrorsOnNegativeWritten)
    test(_TestCopyAtCapSucceedsBoth)
    test(_TestCopyTruncatedClampsAtCapPlusOne)
    test(_TestCopyExactErrorsAtCapPlusOne)
    test(_TestCopyArrayTruncatedClampsAtCapPlusOne)
    test(_TestCopyArrayExactErrorsAtCapPlusOne)

    // bzero behaviour
    test(_TestBzeroTrueZerosTail)
    test(_TestBzeroFalsePreservesTail)
    test(_TestWriteArrayBzeroTrueZerosTail)
    test(_TestWriteArrayBzeroFalsePreservesTail)

    // Reset
    test(_TestResetClearsWritten)
    test(_TestResetZerosBytes)

    // Properties
    test(Property2UnitTest[String, USize](_PropWriteStringRoundTrip))
    test(Property2UnitTest[String, USize](_PropWriteArrayRoundTrip))
    test(Property2UnitTest[String, USize](_PropWriteReturnsIffFits))
    test(Property2UnitTest[String, USize](_PropOversizeWriteIsNoOp))
    test(Property2UnitTest[String, USize](_PropAllocatedInvariant))


// ===========================================================================
// CBox
// ===========================================================================

class \nodoc\ iso _TestCBoxBasic is UnitTest
  fun name(): String => "cbox/basic_read_write"

  fun apply(h: TestHelper) =>
    let b = CBox[U64](42)
    h.assert_eq[U64](42, b.value)
    b.value = 99
    h.assert_eq[U64](99, b.value)

class \nodoc\ iso _TestCBoxIntFamily is UnitTest
  """
  Spot-check that CBox is usable across several Int instantiations.
  We don't enumerate every Int — that would be testing the type system,
  not CBox. Pick representatives covering signed/unsigned and width.
  """
  fun name(): String => "cbox/int_family"

  fun apply(h: TestHelper) =>
    let bu8 = CBox[U8](0)
    bu8.value = U8.max_value()
    h.assert_eq[U8](U8.max_value(), bu8.value)

    let bi8 = CBox[I8](0)
    bi8.value = I8.min_value()
    h.assert_eq[I8](I8.min_value(), bi8.value)

    let bi128 = CBox[I128](0)
    bi128.value = I128.min_value()
    h.assert_eq[I128](I128.min_value(), bi128.value)

    let bus = CBox[USize](0)
    bus.value = USize.max_value()
    h.assert_eq[USize](USize.max_value(), bus.value)

class \nodoc\ iso _TestWrittenSizePtrIdentity is UnitTest
  """
  written_size_ptr() must return the same CBox the buffer reads through
  for get_written_size(). Mutations through the returned box must be
  visible to subsequent get/copy calls — that's the whole reason this
  pointer-out-param exists.
  """
  fun name(): String => "cbuffer/written_size_ptr/identity"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](16)
    let wbox = buf.written_size_ptr()
    wbox.value = 5
    h.assert_eq[ISize](5, buf.get_written_size())
    wbox.value = -1
    h.assert_eq[ISize](-1, buf.get_written_size())
    buf.set_written_size(7)
    h.assert_eq[ISize](7, wbox.value)


// ===========================================================================
// CBuffer construction
// ===========================================================================

class \nodoc\ iso _TestAllocatedReturnsSize is UnitTest
  fun name(): String => "cbuffer/allocated_returns_size"

  fun apply(h: TestHelper) =>
    h.assert_eq[USize](16, CBuffer[ISize](16).allocated())
    h.assert_eq[USize](1, CBuffer[ISize](1).allocated())
    h.assert_eq[USize](4096, CBuffer[ISize](4096).allocated())

class \nodoc\ iso _TestInitialWrittenIsZero is UnitTest
  fun name(): String => "cbuffer/initial_written_is_zero"

  fun apply(h: TestHelper) =>
    h.assert_eq[ISize](0, CBuffer[ISize](64).get_written_size())

class \nodoc\ iso _TestCreateZeroFilled is UnitTest
  """
  After create(N), the buffer's N bytes must be zero. The only way to
  observe the bytes is via copy_*_truncated: bump written_size to N,
  copy out, expect all zeros.
  """
  fun name(): String => "cbuffer/create_is_zero_filled"

  fun apply(h: TestHelper) ? =>
    let cap: USize = 32
    let buf = CBuffer[ISize](cap)
    buf.set_written_size(cap.isize())
    let bytes: Array[U8] val = buf.copy_array_truncated()?
    h.assert_eq[USize](cap, bytes.size())
    for b in bytes.values() do
      h.assert_eq[U8](0, b)
    end


// ===========================================================================
// Write — example-based boundaries
// ===========================================================================

class \nodoc\ iso _TestWriteEmpty is UnitTest
  fun name(): String => "cbuffer/write/empty"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](8)
    h.assert_true(buf.write(""))
    h.assert_eq[ISize](0, buf.get_written_size())
    h.assert_eq[USize](0, buf.copy_string()?.size())

class \nodoc\ iso _TestWriteAtCap is UnitTest
  fun name(): String => "cbuffer/write/at_cap"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](5)
    h.assert_true(buf.write("hello"))
    h.assert_eq[ISize](5, buf.get_written_size())
    h.assert_eq[String]("hello", buf.copy_string()?)

class \nodoc\ iso _TestWriteOverCapReturnsFalse is UnitTest
  fun name(): String => "cbuffer/write/over_cap_returns_false"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](4)
    h.assert_false(buf.write("hello"))

class \nodoc\ iso _TestWriteOverCapLeavesStateUntouched is UnitTest
  """
  The contract says oversize writes are *refused* — the buffer must be
  unchanged. Pre-fill, attempt oversize, verify both written_size and
  bytes are exactly what they were.
  """
  fun name(): String => "cbuffer/write/over_cap_no_op"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](4)
    h.assert_true(buf.write("abcd"))
    let before_written = buf.get_written_size()
    let before_bytes: Array[U8] val = buf.copy_array()?

    h.assert_false(buf.write("hello"))
    h.assert_eq[ISize](before_written, buf.get_written_size())
    h.assert_array_eq[U8](before_bytes, buf.copy_array()?)

class \nodoc\ iso _TestWriteArrayEmpty is UnitTest
  fun name(): String => "cbuffer/write_array/empty"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](8)
    let empty: Array[U8] val = recover val Array[U8] end
    h.assert_true(buf.write_array(empty))
    h.assert_eq[ISize](0, buf.get_written_size())
    h.assert_eq[USize](0, buf.copy_array()?.size())

class \nodoc\ iso _TestWriteArrayAtCap is UnitTest
  fun name(): String => "cbuffer/write_array/at_cap"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](3)
    let arr: Array[U8] val = recover val [as U8: 0x10; 0x20; 0x30] end
    h.assert_true(buf.write_array(arr))
    h.assert_eq[ISize](3, buf.get_written_size())
    h.assert_array_eq[U8](arr, buf.copy_array()?)

class \nodoc\ iso _TestWriteArrayOverCapReturnsFalse is UnitTest
  fun name(): String => "cbuffer/write_array/over_cap_returns_false"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](2)
    let arr: Array[U8] val = recover val [as U8: 1; 2; 3] end
    h.assert_false(buf.write_array(arr))


// ===========================================================================
// copy_* boundary semantics — the truncated/non-truncated divergence is
// the load-bearing distinction; test both sides at every transition.
// ===========================================================================

class \nodoc\ iso _TestCopyErrorsOnNegativeWritten is UnitTest
  """
  written_size < 0 is a caller-defined sentinel. All four copy_* methods
  must error on it — none should silently return data.
  """
  fun name(): String => "cbuffer/copy/negative_written_errors"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](8)
    buf.set_written_size(-1)
    try buf.copy_string()?; h.fail("copy_string should error on negative") end
    try buf.copy_string_truncated()?
      h.fail("copy_string_truncated should error on negative") end
    try buf.copy_array()?; h.fail("copy_array should error on negative") end
    try buf.copy_array_truncated()?
      h.fail("copy_array_truncated should error on negative") end

class \nodoc\ iso _TestCopyAtCapSucceedsBoth is UnitTest
  """
  At written_size == cap, both copy_string and copy_string_truncated
  must succeed — this is the legal upper edge.
  """
  fun name(): String => "cbuffer/copy/at_cap_both_succeed"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](4)
    h.assert_true(buf.write("abcd"))
    h.assert_eq[String]("abcd", buf.copy_string()?)
    h.assert_eq[String]("abcd", buf.copy_string_truncated()?)

class \nodoc\ iso _TestCopyTruncatedClampsAtCapPlusOne is UnitTest
  """
  When a C caller reports written_size == cap + 1 (e.g. truncation
  signalled out-of-band), copy_string_truncated must clamp to cap
  rather than walk off the allocation.
  """
  fun name(): String => "cbuffer/copy_string_truncated/clamps"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](4)
    h.assert_true(buf.write("abcd"))
    buf.set_written_size(5)
    let s: String val = buf.copy_string_truncated()?
    h.assert_eq[USize](4, s.size())
    h.assert_eq[String]("abcd", s)

class \nodoc\ iso _TestCopyExactErrorsAtCapPlusOne is UnitTest
  """
  Counterpart to the truncated-clamps test: copy_string (non-truncating)
  must error rather than clamp. This is the documented difference.
  """
  fun name(): String => "cbuffer/copy_string/errors_over_cap"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](4)
    buf.write("abcd")
    buf.set_written_size(5)
    try buf.copy_string()?; h.fail("copy_string should error past cap") end

class \nodoc\ iso _TestCopyArrayTruncatedClampsAtCapPlusOne is UnitTest
  fun name(): String => "cbuffer/copy_array_truncated/clamps"

  fun apply(h: TestHelper) ? =>
    let buf = CBuffer[ISize](3)
    let arr: Array[U8] val = recover val [as U8: 1; 2; 3] end
    h.assert_true(buf.write_array(arr))
    buf.set_written_size(4)
    let out: Array[U8] val = buf.copy_array_truncated()?
    h.assert_array_eq[U8](arr, out)

class \nodoc\ iso _TestCopyArrayExactErrorsAtCapPlusOne is UnitTest
  fun name(): String => "cbuffer/copy_array/errors_over_cap"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](3)
    buf.write_array(recover val [as U8: 1; 2; 3] end)
    buf.set_written_size(4)
    try buf.copy_array()?; h.fail("copy_array should error past cap") end


// ===========================================================================
// bzero behaviour — set up a long write, follow with a shorter write,
// then peek at the tail by manually setting written_size back up.
// ===========================================================================

class \nodoc\ iso _TestBzeroTrueZerosTail is UnitTest
  """
  With bzero=true, a shorter follow-up write must zero everything past
  its own length. Verify by bumping written_size back to the original
  length and copying — the tail must be zeros.
  """
  fun name(): String => "cbuffer/write/bzero_true_zeros_tail"

  fun apply(h: TestHelper) ? =>
    let cap: USize = 10
    let buf = CBuffer[ISize](cap)
    h.assert_true(buf.write("AAAAAAAAAA"))
    h.assert_true(buf.write("B" where bzero = true))
    buf.set_written_size(cap.isize())
    let bytes: Array[U8] val = buf.copy_array_truncated()?
    h.assert_eq[USize](cap, bytes.size())
    h.assert_eq[U8]('B', bytes(0)?)
    var i: USize = 1
    while i < cap do
      h.assert_eq[U8](0, bytes(i)?)
      i = i + 1
    end

class \nodoc\ iso _TestBzeroFalsePreservesTail is UnitTest
  """
  With bzero=false, the bytes past the new write must retain the prior
  content. Same setup; assert the tail is the old 'A's, not zeros.
  """
  fun name(): String => "cbuffer/write/bzero_false_preserves_tail"

  fun apply(h: TestHelper) ? =>
    let cap: USize = 10
    let buf = CBuffer[ISize](cap)
    h.assert_true(buf.write("AAAAAAAAAA"))
    h.assert_true(buf.write("B" where bzero = false))
    buf.set_written_size(cap.isize())
    let bytes: Array[U8] val = buf.copy_array_truncated()?
    h.assert_eq[USize](cap, bytes.size())
    h.assert_eq[U8]('B', bytes(0)?)
    var i: USize = 1
    while i < cap do
      h.assert_eq[U8]('A', bytes(i)?)
      i = i + 1
    end

class \nodoc\ iso _TestWriteArrayBzeroTrueZerosTail is UnitTest
  fun name(): String => "cbuffer/write_array/bzero_true_zeros_tail"

  fun apply(h: TestHelper) ? =>
    let cap: USize = 6
    let buf = CBuffer[ISize](cap)
    let big: Array[U8] val = recover val [as U8: 0xAA; 0xAA; 0xAA; 0xAA; 0xAA; 0xAA] end
    let small: Array[U8] val = recover val [as U8: 0xBB] end
    h.assert_true(buf.write_array(big))
    h.assert_true(buf.write_array(small where bzero = true))
    buf.set_written_size(cap.isize())
    let bytes: Array[U8] val = buf.copy_array_truncated()?
    h.assert_eq[U8](0xBB, bytes(0)?)
    var i: USize = 1
    while i < cap do
      h.assert_eq[U8](0, bytes(i)?)
      i = i + 1
    end

class \nodoc\ iso _TestWriteArrayBzeroFalsePreservesTail is UnitTest
  fun name(): String => "cbuffer/write_array/bzero_false_preserves_tail"

  fun apply(h: TestHelper) ? =>
    let cap: USize = 6
    let buf = CBuffer[ISize](cap)
    let big: Array[U8] val = recover val [as U8: 0xAA; 0xAA; 0xAA; 0xAA; 0xAA; 0xAA] end
    let small: Array[U8] val = recover val [as U8: 0xBB] end
    h.assert_true(buf.write_array(big))
    h.assert_true(buf.write_array(small where bzero = false))
    buf.set_written_size(cap.isize())
    let bytes: Array[U8] val = buf.copy_array_truncated()?
    h.assert_eq[U8](0xBB, bytes(0)?)
    var i: USize = 1
    while i < cap do
      h.assert_eq[U8](0xAA, bytes(i)?)
      i = i + 1
    end


// ===========================================================================
// Reset
// ===========================================================================

class \nodoc\ iso _TestResetClearsWritten is UnitTest
  fun name(): String => "cbuffer/reset/clears_written"

  fun apply(h: TestHelper) =>
    let buf = CBuffer[ISize](8)
    h.assert_true(buf.write("hello"))
    h.assert_eq[ISize](5, buf.get_written_size())
    buf.reset()
    h.assert_eq[ISize](0, buf.get_written_size())

class \nodoc\ iso _TestResetZerosBytes is UnitTest
  """
  reset() must zero the actual bytes too, not just written_size.
  Verify by bumping written_size up after reset and copying.
  """
  fun name(): String => "cbuffer/reset/zeros_bytes"

  fun apply(h: TestHelper) ? =>
    let cap: USize = 8
    let buf = CBuffer[ISize](cap)
    h.assert_true(buf.write("ABCDEFGH"))
    buf.reset()
    buf.set_written_size(cap.isize())
    let bytes: Array[U8] val = buf.copy_array_truncated()?
    for b in bytes.values() do
      h.assert_eq[U8](0, b)
    end


// ===========================================================================
// Properties — the load-bearing correctness invariants.
// ===========================================================================

class \nodoc\ iso _PropWriteStringRoundTrip is Property2[String, USize]
  """
  For any string and any cap such that str.size() <= cap, write+copy
  must return a string equal to the original. We use cap = str.size() +
  slack to guarantee fit while still varying cap independently.
  """
  fun name(): String => "cbuffer/prop/write_string_roundtrip"

  fun gen1(): Generator[String] => Generators.byte_string(Generators.u8(), 0, 64)
  fun gen2(): Generator[USize] => Generators.usize(0, 32) // slack above str.size()

  fun ref property2(str: String, slack: USize, h: PropertyHelper) ? =>
    let s: String val = str.clone()
    let cap = s.size() + slack
    let buf = CBuffer[ISize](cap)
    h.assert_true(buf.write(s))
    h.assert_eq[String](s, buf.copy_string()?)

class \nodoc\ iso _PropWriteArrayRoundTrip is Property2[String, USize]
  """
  Same property, but via write_array/copy_array. Uses the string
  generator and converts to Array[U8] val to sidestep the
  Generators.array_of -> ref-array gotcha.
  """
  fun name(): String => "cbuffer/prop/write_array_roundtrip"

  fun gen1(): Generator[String] => Generators.byte_string(Generators.u8(), 0, 64)
  fun gen2(): Generator[USize] => Generators.usize(0, 32)

  fun ref property2(str: String, slack: USize, h: PropertyHelper) ? =>
    let arr: Array[U8] val = str.array()
    let cap = arr.size() + slack
    let buf = CBuffer[ISize](cap)
    h.assert_true(buf.write_array(arr))
    h.assert_array_eq[U8](arr, buf.copy_array()?)

class \nodoc\ iso _PropWriteReturnsIffFits is Property2[String, USize]
  """
  Mixed valid/invalid: write returns true *iff* str.size() <= cap.
  Generators are independent, so every run is either valid or invalid;
  the iff-assertion catches both directions of error.
  """
  fun name(): String => "cbuffer/prop/write_returns_iff_fits"

  fun gen1(): Generator[String] => Generators.byte_string(Generators.u8(), 0, 64)
  fun gen2(): Generator[USize] => Generators.usize(0, 64)

  fun ref property2(str: String, cap: USize, h: PropertyHelper) =>
    let s: String val = str.clone()
    let buf = CBuffer[ISize](cap)
    let fits = s.size() <= cap
    h.assert_eq[Bool](fits, buf.write(s))

class \nodoc\ iso _PropOversizeWriteIsNoOp is Property2[String, USize]
  """
  When the write would overflow, the buffer must be untouched.
  Pre-fill, attempt oversize, assert observable state is identical.
  """
  fun name(): String => "cbuffer/prop/oversize_write_no_op"

  fun gen1(): Generator[String] => Generators.byte_string(Generators.u8(), 1, 32)
  fun gen2(): Generator[USize] => Generators.usize(1, 32) // overflow amount

  fun ref property2(prefill: String, overflow: USize, h: PropertyHelper) ? =>
    let p: String val = prefill.clone()
    let cap = p.size()
    let buf = CBuffer[ISize](cap)
    h.assert_true(buf.write(p))
    let before_written = buf.get_written_size()
    let before_bytes: Array[U8] val = buf.copy_array()?

    let oversize: String val = recover val
      let acc = String(cap + overflow)
      var i: USize = 0
      while i < (cap + overflow) do
        acc.push('X')
        i = i + 1
      end
      acc
    end
    h.assert_false(buf.write(oversize))
    h.assert_eq[ISize](before_written, buf.get_written_size())
    h.assert_array_eq[U8](before_bytes, buf.copy_array()?)

class \nodoc\ iso _PropAllocatedInvariant is Property2[String, USize]
  """
  allocated() is fixed at construction. After any sequence of writes,
  resets, and set_written_size calls, it must still equal the
  construction size.
  """
  fun name(): String => "cbuffer/prop/allocated_is_invariant"

  fun gen1(): Generator[String] => Generators.byte_string(Generators.u8(), 0, 32)
  fun gen2(): Generator[USize] => Generators.usize(1, 64)

  fun ref property2(s: String, cap: USize, h: PropertyHelper) =>
    let str: String val = s.clone()
    let buf = CBuffer[ISize](cap)
    buf.write(str)
    h.assert_eq[USize](cap, buf.allocated())
    buf.reset()
    h.assert_eq[USize](cap, buf.allocated())
    buf.set_written_size(-1)
    h.assert_eq[USize](cap, buf.allocated())
    buf.set_written_size((cap + 100).isize())
    h.assert_eq[USize](cap, buf.allocated())
