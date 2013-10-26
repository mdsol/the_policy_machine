# This file contains helper methods to test policy machine integration with storage adapters.

def if_implements(storage_adapter, meth, *args,&block)
  storage_adapter.send(meth,*args,&block)
rescue NotImplementedError => e
  pending(e.message)
end
