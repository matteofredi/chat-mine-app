import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:convert';

class MessagingScreen extends StatefulWidget {
  final String username;
  final String accessToken;

  const MessagingScreen(
      {super.key, required this.username, required this.accessToken});

  @override
  _MessagingScreenState createState() => _MessagingScreenState();
}

class _MessagingScreenState extends State<MessagingScreen> {
  String apiUrl = dotenv.env['API_URL'] ?? 'localhost:8000/';
  String webSocketUrl = dotenv.env['WEB_SOCKET_URL'] ?? 'ws://127.0.0.1:8000/';
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _messages = [];
  final List<Map<String, dynamic>> _friends = [];
  int? _selectedFriendId;
  String? _selectedFriendName;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _fetchFriends();
  }

  Future<void> _fetchFriends() async {
    final url = Uri.parse('${apiUrl}users/me/friends');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer ${widget.accessToken}',
        'accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _friends.addAll(data.map((friend) => {
              'id': friend['id'],
              'name': friend['name'],
              'status': friend['status'],
            }));
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load friends')),
      );
    }
  }

  Future<void> _fetchChatHistory(int friendId, String friendName) async {
    final url =
        Uri.parse('${apiUrl}chat/history?friend_id=$friendId');
    final response = await http.get(
      url,
      headers: {
        'Authorization': 'Bearer ${widget.accessToken}',
        'accept': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      setState(() {
        _selectedFriendId = friendId;
        _selectedFriendName = friendName;
        _messages.clear();
        _messages.addAll(data.map((message) => {
              'id': message['id'],
              'fromUser': message['from_user'],
              'content': message['content'],
              'isRead': message['is_read'],
            }));
      });
      _connectToWebSocket(friendId);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load chat history')),
      );
    }
  }

  void _connectToWebSocket(int friendId) {
    _channel = WebSocketChannel.connect(
      Uri.parse('${webSocketUrl}ws/$friendId?token=${widget.accessToken}'),
    );

    _channel!.stream.listen((message) {
      setState(() {
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch,
          'fromUser': false,
          'content': message,
          'isRead': true,
        });
      });
    });
  }

  void _sendMessage() {
    if (_controller.text.isNotEmpty && _selectedFriendId != null) {
      final message = _controller.text;
      _channel?.sink.add(message);
      setState(() {
        _messages.add({
          'id': DateTime.now().millisecondsSinceEpoch,
          'fromUser': true,
          'content': _controller.text,
          'isRead': false,
        });
        _controller.clear();
      });
    }
  }

  void _clearChatHistory() {
    setState(() {
      _messages.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Chat history cleared')),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Messaging App'),
        backgroundColor: Colors.green[700],
        actions: [
          IconButton(
            icon: Icon(Icons.delete),
            onPressed: _clearChatHistory,
          ),
        ],
      ),
      body: Row(
        children: [
          Container(
            width: 250,
            decoration: BoxDecoration(
              color: Colors.green[100],
              border: Border(
                right: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: ListView(
              children: _friends.map((friend) {
                return InkWell(
                  onTap: () {
                    _fetchChatHistory(friend['id'], friend['name']);
                  },
                  hoverColor: Colors.green[200],
                  child: ListTile(
                    leading: CircleAvatar(
                      child: Text(friend['name'][0]),
                      backgroundColor: Colors.green,
                    ),
                    title: Text(friend['name']),
                    subtitle: Text(friend['status']),
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      itemCount: _messages.length,
                      itemBuilder: (context, index) {
                        final message = _messages[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: Align(
                            alignment: message['fromUser']
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Chip(
                              label: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8.0, vertical: 4.0),
                                child: Text(message['content']),
                              ),
                              backgroundColor: message['fromUser']
                                  ? Colors.green[200]
                                  : Colors.grey[300],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: 'Enter your message',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              filled: true,
                              fillColor: Colors.grey[200],
                            ),
                            onSubmitted: (value) {
                              _sendMessage();
                            },
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.send),
                          onPressed: _sendMessage,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
