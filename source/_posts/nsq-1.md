---
title: nsq-1
date: 2020-06-30 00:23:05
tags: [nsq]
---

# nsq 源码分析-1

## 前言

前几周在学习 raft，但由于 raft 需要耗费的周期比较长，打算等到大四了再好好学一学论文和啃一啃 raft 源码（其实我已经把 raft 的 log 层、log 存储、process 等源码啃的差不多了，剩下最难啃的 raft 层和 node 层了。。。），最近不搞这个了，先认真备战秋招。

这两周学习 nsq，是因为之前在公司用到消息队列的场景还挺多的（客户端打点，日志等之类的都会用到），而我基本没学过 java，看不了 kafka，所以把用 go 编写的 nsq 拿来啃一啃。

<!--more-->

我看的是 nsq 的早期版本，想借此来循序渐进。感兴趣的可以在这里下载：[nsq-github](https://github.com/nsqio/nsq/tree/fbf26b502e8a3c407cfb9aa3ceb7076d2632d05e)

```
tree --dirsfirst -L 1 -I '*test*' -P '*.go'
```

![image-20200630003836745](/images/image-20200630003836745.png)

通过命令可以看到一共 13 个文件。下面就通过一个消息从消费者通过 http->nsq->consummer 讲解一条消息在 nsq 中的移动过程。下一张详细讲解每个文件中主要函数的作用。敬请期待~

## msg 移动过程

首先说明一点，nsg 中只要涉及到 channel 的，都是协程和协程之间的通信。nsq 启动时会启动很多协程的。

### start

首先，消费者通过调用 http 接口进入代码：

![image-20200630004832893](/images/image-20200630004832893.png)

获取到传入的参数后，通过调用 GetTopic 获取到此 topicName 对应的 topic。

![image-20200630005420219](/images/image-20200630005420219.png)

GetTopic 这个函数写的还是比较有趣的，在新建了一个 interface 型的变量之后，将 topicName 和 topicChan 传给 newTopicChan 后等待此 interface 变量发送返回的消息。

![image-20200630005556375](/images/image-20200630005556375.png)

这个是 newTopic 的定义：

![image-20200630005910119](/images/image-20200630005910119.png)

newTopic 接收到消息后，查看这个 topicName 是否在 topicMap 中，如果存在，取出 topic 给上面的 channel 发送消息，如果不在，将新建 key-value 并存入 map 中，并将此 topic 传给的 channel。

获取到 topic 后返回，调用`topic.PutMessage(NewMessage(buf.Bytes()))`，将 msg 传给 topic 的 incomingMessageChan。

![image-20200630011105603](/images/image-20200630011105603.png)

接下来会在这里调用：

![image-20200630011637880](/images/image-20200630011637880.png)

如果执行的是 default，则放入 topic 对应的 queue 中（topic 的 queue 是消息过多而设置的，channel 中存的是每一个消费者需要消费的消息，两者有着本质的区别，虽然底层 queue 代码一样），然后存起来。等到合适的时机在从队列取出，然后将消息存入 channel 中的 queue 中（和下面执行几乎一样的代码）。

否则将消息送入 msgChan：

![image-20200630014257134](/images/image-20200630014257134.png)

将 msg 存入 channel 对应的 queue 中：

![image-20200630020606952](/images/image-20200630020606952.png)

![image-20200630020912765](/images/image-20200630020912765.png)

如果是 default 类似于上面的，存入 channel 的 queue 中（然后等适当时机从下图的 ReadReadyChan 出来），否则进入 msgchan：

![image-20200630021140489](/images/image-20200630021140489.png)

![image-20200630022759927](/images/image-20200630022759927.png)

执行`c.RequeueMessage(UuidToStr(msg.Uuid()))`：

![image-20200630023027618](/images/image-20200630023027618.png)

![image-20200630023123403](/images/image-20200630023123403.png)

将消息取出后又放回去。是将消息放入队列末尾了，因为 nsq 并不像其他消息队列一样需要保证消息的顺序，这也是 nsq 速度快的一点原因。

但是正如《隐秘的角落一样》，这样一直循环是不是毫无意义，那么是在什么时候发送给的消费者？

答案就在 nsq/channel 的 GetMessage 中：

![image-20200630023434197](/images/image-20200630023434197.png)

这个函数执行完之后会 break，向上查找可知是 protocol 调用：

![image-20200630023535944](/images/image-20200630023535944.png)

但是这个 GET 函数并没有被调用过，此时联想到 go 的反射机制不难推出答案：

![image-20200630023620026](/images/image-20200630023620026.png)

消费者在 IOLoop 中通过 body 发现客户端的 cmd 是 get 请求，通过反射调用 get 函数后，等待消息的到来。

还有两个细节需要注意一下：

* 生产者发送时的格式为：http 头 | body，http 头中有 topic 信息，body 中的都是对应的消息。
* 发送者发送的消息格式为：版本号（4字节，区分唯一的 Protocol）,cmd\r\n cmd\r\n。
* 发送者接受的消息格式应该为：uuid（唯一区分 msg 用的） + body。

至此流程基本推导完毕。
