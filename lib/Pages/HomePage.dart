import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../Common/Routers.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text("UNIVERSIDAD DE ENVIGADO",
          style: TextStyle(
            color: Colors.blue.shade900,
            fontSize: 30,
            fontWeight: FontWeight.w900
          )),
          Text("FACULTAD DE INGENIERIA"),
          Image.asset('assets/Logo.jpg'),
          GestureDetector(
            onTap: () => context.push(Routers.login),
            child: Container(
              width: 250,
              height: 80,
              padding: EdgeInsets.all(30),
              margin: EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(16)
              ),
              child: Text("SUSCRIPCIONES"),
            ),
          ),
        ],
      ),
    );
  }
}
