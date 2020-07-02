---
title: nsq源码刨析
date: 2020-07-02 16:15:20
tags: [nsq]
---

## 概述

本博客是讲解 nsq 中一些文件中的主要函数的作用，另外，我个人还针对 nsq v0.1.1 版本的相关代码实现做了一些注释笔记，感兴趣的可以自行阅读：[nsq-0.1.1-ghorges](https://github.com/ghorges/nsq-0.1.1-ghorges)

## nsq.go

main 函数在这里执行，这里主要启动了 3 个协程（算上主协程共四个）：

![image-20200702162701931](/images/image-20200702162701931.png)

## queue.go && diskqueue.go

这个函数就不详细讲了，因为 nsq 的队列不是一个 msg 有序的队列，而是如果消息塞满了，比如 topic 或者 channel 中消息放不下了，那么就会放到它们的 queue 中，这也可能会导致消息失序。当然了，**nsq 并不关心是否失序**，一个 msg 也可以被下发多次（一定会成功，否则就会重试），所以业务方需要有幂等性。

先讲 queue 是因为后面的 topic 和 channel 会用到 queue，而 queue 基本没有依赖。

由这个 interface 可以看出 queue 定义了 get、put、readreadychan、close 接口。

![image-20200702164006939](/images/image-20200702164006939.png)

这里仅说说 ReadReadyChan，其他几个简单明了，就不加以赘述。这个接口返回的是一个`chan int`，调用者一般会使用`<-ReadReadyChan()`进行等待，如果队列中有消息，那么会给这个 chan 赋值（或者可以用户自己定义，等信息到达一定数量再进行赋值）。

diskqueue 是实现了 queue 的磁盘版。

## topic.go

不同的 topicName 都有各自的 topic。

![image-20200702163222651](/images/image-20200702163222651.png)

NewTopic 是在每次有新 topicName 时调用的，并且每次新建 topic 的时候，都会建立此 topic 的一个 Router 循环。

请看下面两张图，这个循环主要有两个 chan：一个是新建立 channel 时触发的，并对这个 topic 建立一个循环（这个函数是将 msg 放入所有 channel）；另一个是当每次有生产者将消息发送到 nsq 中后触发的，topic 将此消息写到每一个 channel 中，如果 chan 被写满了，那么会先写到 queue 中（进入到 default 中），等到合适的时机在返回此 chan 中。

![image-20200702163517324](/images/image-20200702163517324.png)

![image-20200702163633711](/images/image-20200702163633711.png)

topicFactory 是 main 启动的一个协程，每次有 http连接来的时候会调用 newTopicChan。

![image-20200702172346576](/images/image-20200702172346576.png)

## channel.go

channel 和 topic 很多地方代码很像。因为放入队列等操作几乎是一样的，但是不同点也很明显。

当消费者发送的 cmd 为 FIN 和 REQ 的时候，分别会执行这两个函数：

![image-20200702173446652](/images/image-20200702173446652.png)

这个函数是将需要发送的消息返回到 protocol 中，并且给 inFlightMessageChan 赋值，inFlightMessageChan 的作用是将此 msg 保存一段时间，等客户端发送 cmd 为 FIN 信号后，会将这个 msg 清除；或者客户端发送 REQ/超时，将这个消息重新放入 chan 中。

![image-20200702173712189](/images/image-20200702173712189.png)

channel 的 Router 中有两个 select，一个是处理消费者发来的信息，另一个是处理 topic 发来的信息。

![image-20200702181255128](/images/image-20200702181255128.png)

## protocol.go && protocol_v1.go

protocol 接口定义了 IOLoop。

![image-20200702181445852](/images/image-20200702181445852.png)

protocol_v1 的实现中使用了反射机制，将反射的函数执行。

![image-20200702181605857](/images/image-20200702181605857.png)

![image-20200702181623300](/images/image-20200702181623300.png)

消费者一共可以调用这五个函数。

![image-20200702181739267](/images/image-20200702181739267.png)

## client.go

client 中有一个状态机，每次执行 protocol_v1 的函数时，都会改变状态机。注意：上述函数的执行必须是有序的，否则就会给消费者返回错误。

![image-20200702181834014](/images/image-20200702181834014.png)

![image-20200702181908081](/images/image-20200702181908081.png)

client 中还有一个 Handle 是消费者通过 tcp 连接并处理完毕后会进入这里。通过消费者发送的消息判断使用哪个 protocol。

![image-20200702182123785](/images/image-20200702182123785.png)

分析到此结束。