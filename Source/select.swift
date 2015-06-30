/*
* Select (select.swift) - Please be Safe
*
* Copyright (C) 2015 ONcast, LLC. All Rights Reserved.
* Created by Josh Baker (joshbaker77@gmail.com)
*
* This software may be modified and distributed under the terms
* of the MIT license.  See the LICENSE file for details.
*/

import Foundation

private protocol ItemAny {
    func register(cond: Cond)
    func unregister(cond: Cond)
    func get() -> Bool;
    func call()
}

private class Item<T> : ItemAny {
    var closed = false
    var msg : T?
    var chan : Chan<T>?
    var caseBlock : ((T?)->())?
    var defBlock : (()->())?
    init(_ chan: Chan<T>?, _ caseBlock: ((T?)->())?, _ defBlock: (()->())?){
        (self.chan, self.caseBlock, self.defBlock) = (chan, caseBlock, defBlock)
    }
    func register(cond: Cond){
        if let chan = chan {
            chan.cond.mutex.lock()
            defer { chan.cond.mutex.unlock() }
            chan.gconds += [cond]
        }
    }
    func unregister(cond: Cond){
        if let chan = chan {
            chan.cond.mutex.lock()
            defer { chan.cond.mutex.unlock() }
            for var i = 0; i < chan.gconds.count; i++ {
                if chan.gconds[i] === cond {
                    chan.gconds.removeAtIndex(i)
                    return
                }
            }
        }
    }
    func get() -> Bool {
        if let chan = chan {
            let (msg, closed, ready) = chan.receive(false)
            if ready {
                self.msg = msg
                self.closed = closed
                return true
            }
        }
        return false
    }
    func call() {
        if let block = caseBlock {
            block(msg)
        } else if let block = defBlock {
            block()
        }
    }
    
}

private class ChanGroup {
    var cond = Cond(Mutex())
    var items = [Int: ItemAny]()
    var ids = [Int]()
    func addCase<T>(chan: Chan<T>, _ block: (T?)->()){
        if items[chan.id] != nil {
            fatalError("selecting channel twice")
        }
        items[chan.id] = Item<T>(chan, block, nil)
        ids.append(chan.id)
    }
    func addDefault(block: ()->()){
        if items[0] != nil {
            fatalError("selecting default twice")
        }
        items[0] = Item<Void>(nil, nil, block)
    }
    func select(){
        let rids = randomInts(ids.count)
        var citems = [ItemAny]()
        for i in rids {
            if let item = items[ids[i]] {
                citems.append(item)
            }
        }
        var ret : ItemAny?
        for item in citems {
            item.register(cond)
        }
        defer {
            for item in citems {
                item.unregister(cond)
            }
            if let item = ret {
                item.call()
            }
        }
        for ;; {
            for item in citems {
                if item.get() {
                    ret = item
                    return
                }
            }
            if items[0] != nil {
                ret = items[0]
                return
            }
            cond.mutex.lock()
            cond.wait(0.25)
            cond.mutex.unlock()
        }
    }
    func randomInts(count : Int) -> [Int]{
        var ints = [Int](count: count, repeatedValue:0)
        for var i = 0; i < count; i++ {
            ints[i] = i
        }
        for var i = 0; i < count; i++ {
            let r = Int(arc4random()) % count
            let t = ints[i]
            ints[i] = ints[r]
            ints[r] = t
        }
        return ints
    }
}


private let selectMutex = Mutex()
private var selectStack : [ChanGroup] = []

public func _select(block: ()->()){
    let group = ChanGroup()
    selectMutex.lock()
    selectStack += [group]
    block()
    selectStack.removeLast()
    selectMutex.unlock()
    group.select()
}

public func _case<T>(chan: Chan<T>, block: (T?)->()){
    if let group = selectStack.last{
        group.addCase(chan, block)
    }
}
public func _default(block: ()->()){
    if let group = selectStack.last{
        group.addDefault(block)
    }
}


