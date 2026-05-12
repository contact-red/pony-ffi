use @memcpy[Pointer[U8] ref](dest: Pointer[None] tag, src: Pointer[None] tag, size: USize)
use @memmove[Pointer[U8] ref](dest: Pointer[None] tag, src: Pointer[None] tag, size: USize)
use @pony_ctx[Pointer[None]]()
use @pony_alloc[Pointer[U8] ref](ctx: Pointer[None], size: USize)
use @explicit_bzero[None](ptr: Pointer[U8] tag, size: USize)

class CBuffer[A: Integer[A] val = ISize]
  var _ptr: Pointer[U8] ref
  var _allocated: USize = 0
  var _written: CBox[A] = CBox[A](A.from[USize](0))

  new create(size: USize, bzero: Bool = true) =>
    """
    Allocate a buffer of `size` bytes, zero-filled. CBuffer explicitly
    does not support resize.  To grow, construct a new CBuffer and copy.

    The type parameter `A` selects the numeric type backing `written_size`.
    It defaults to `ISize` so the negative-sentinel idiom remains available;
    callers wanting an unsigned width (e.g. `CBuffer[U32]`) can override.
    """
    _ptr = @pony_alloc(@pony_ctx(), size)
    _allocated = size
    if (bzero) then @explicit_bzero(_ptr, _allocated) end

  fun allocated(): USize =>
    """
    Returns allocated capacity in bytes.
    """
    _allocated

  fun ref reset() =>
    """
    Zero-fill the buffer and reset `written_size` to 0.
    """
    @explicit_bzero(_ptr, _allocated)
    _written.value = A.from[USize](0)

  fun ref ptr(): Pointer[U8] ref =>
    """
    Base pointer for FFI calls.
    """
    _ptr

  fun get_written_size(): A =>
    """
    Most recent filled length, in bytes. When `A` is signed, callers may
    use negative values as out-of-band sentinels.
    """
    _written.value

  fun ref set_written_size(n: A) =>
    """
    Set `written_size` from Pony code. Useful when a caller wants to mark
    the buffer with a sentinel without going through C.
    """
    _written.value = n

  fun ref written_size_ptr(): CBox[A] =>
    """
    Address of the `written_size` field, for C functions that report the
    filled length through an out-parameter.
    """
    _written

  fun ref write(str: String val, bzero: Bool = true): Bool =>
    """
    Copy `str` into the buffer and set `written_size` to its length. Returns
    false (leaving the buffer unchanged) if `str` exceeds capacity.

    Refuses truncation rather than silently dropping bytes.

    bzero can be disabled for performance reasons if dealing with massive
    allocations in hot-paths.  You probably shouldn't unless you're certain
    you know what you're doing.
    """
    if str.size() > _allocated then return false end
    if (bzero) then @explicit_bzero(_ptr, _allocated) end
    @memcpy(_ptr, str.cpointer(), str.size())
    _written.value = A.from[USize](str.size())
    true

  fun ref write_array(arr: Array[U8] val, bzero: Bool = true): Bool =>
    """
    Copy `arr` into the buffer and set `written_size` to its length. Returns
    false (leaving the buffer unchanged) if the buffer is not allocated or
    `arr` exceeds capacity.

    Refuses truncation rather than silently dropping bytes.

    bzero can be disabled for performance reasons if dealing with massive
    allocations in hot-paths.  You probably shouldn't unless you're certain
    you know what you're doing.
    """
    if arr.size() > _allocated then return false end
    if (bzero) then @explicit_bzero(_ptr, _allocated) end
    @memcpy(_ptr, arr.cpointer(), arr.size())
    _written.value = A.from[USize](arr.size())
    true

  fun ref copy_string_truncated(): String iso^ ? =>
    """
    Copy the filled region out as a String. Errors if the buffer is not
    allocated or `written_size` is negative. If `written_size` exceeds
    `cap()` (e.g. a C caller reporting truncation), the result is clamped
    to `cap()` rather than walking off the end of the allocation.
    """
    if _written.value < A.from[USize](0) then error end
    let size = if _written.value.usize() > _allocated then _allocated else _written.value.usize() end
    String.from_cpointer(_ptr, size, size).clone()

  fun copy_array_truncated(): Array[U8] iso^ ? =>
    """
    Copy the filled region out as an Array[U8]. Same error and clamp
    semantics as `copy_string_truncated()`.
    """
    if _written.value < A.from[USize](0) then error end
    let size = if _written.value.usize() > _allocated then _allocated else _written.value.usize() end
    let rv: Array[U8] iso = recover iso Array[U8].init(0, size) end
    @memcpy(rv.cpointer(), _ptr, size)
    consume rv

  fun ref copy_string(): String iso^ ? =>
    """
    Copy the filled region out as a String. Errors if the buffer is not
    allocated or `written_size` is negative, or if written_size is greater
    than the allocated space.
    """
    if _written.value < A.from[USize](0) then error end
    let size = _written.value.usize()
    if size > _allocated then error end
    String.from_cpointer(_ptr, size, size).clone()

  fun copy_array(): Array[U8] iso^ ? =>
    """
    Copy the filled region out as an Array[U8]. Same error semantics as
    `copy_string()`.
    """
    if _written.value < A.from[USize](0) then error end
    let size = _written.value.usize()
    if size > _allocated then error end
    let rv: Array[U8] iso = recover iso Array[U8].init(0, size) end
    @memcpy(rv.cpointer(), _ptr, size)
    consume rv

