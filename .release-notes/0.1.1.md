## Initial Release

Contains two types, a struct (CBox), and a class (CBuffer)

### CBox

When you have a C-FFI call that wants to write an integer value to an address that you provide, the typical way to do this is via `addressof`, like this:

```pony
  var myvar: ISize = 0
  @some_ffi_function(addressof myvar)
```

However, since you can't use `addressof` in non-FFI function calls, CBox\[A: Integer\] is a simple Generic Struct to provide this functionality at the expense of a heap allocation:

```pony
    var mycbox: CBox[ISize] = CBox[ISize](0)
    foo(mycbox)
    env.out.print("C returned: " + mycbox.value.string())

  fun foo(mycbox: CBox[ISize]) =>
    @some_ffi_function(mycbox)
```

### CBuffer

A generic C Buffer that can be used to receive data from C-FFI functions that you provide a pointer to, and return the length of the data that was written.  Note, the type backing "written size" is a type parameter (A), since different C-FFI functions report length with differently sized values.

```pony
    var mybuffer: CBuffer[ISize] = CBuffer[ISize](1024)
    @some_ffi_call(mybuffer.ptr(), mybuffer.allocated(), mybuffer.written_size_ptr())

    try
      var string: String iso = mybuffer.copy_string()?
      var array: Array\[U8\] iso = mybuffer.copy_array()?
    else
      Debug.out("Written value is a sentinel or value larger than allocation")
    end
```

Documentation at: [https://pony-ffi.contact.red](https://pony-ffi.contact.red)

