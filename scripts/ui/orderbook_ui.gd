extends Control

var current_symbol: String = "BTCUSDT"

func _ready():
        _connect_signals()
        _request_orderbook()

func _connect_signals():
        if OrderBookManager:
                OrderBookManager.orderbook_updated.connect(_on_orderbook_updated)
        if DataManager:
                DataManager.price_updated.connect(_on_price_updated)

func _request_orderbook():
        if OrderBookManager:
                OrderBookManager.request_orderbook(current_symbol)

func _on_orderbook_updated(symbol: String, bids: Array, asks: Array):
        if symbol == current_symbol:
                _update_bids(bids)
                _update_asks(asks)
                _update_spread(bids, asks)

func _update_bids(bids: Array):
        var container = $VBoxContainer/BidsPanel/BidsContent/BidsScroll/BidsList
        if container:
                for child in container.get_children():
                        child.queue_free()
                for bid in bids.slice(0, 15):
                        var label = Label.new()
                        label.text = "$%.2f | %.4f" % [bid.get("price", 0.0), bid.get("amount", 0.0)]
                        label.add_theme_color_override("font_color", Color(0.0, 0.9, 0.4, 1.0))
                        container.add_child(label)

func _update_asks(asks: Array):
        var container = $VBoxContainer/AsksPanel/AsksContent/AsksScroll/AsksList
        if container:
                for child in container.get_children():
                        child.queue_free()
                for ask in asks.slice(0, 15):
                        var label = Label.new()
                        label.text = "$%.2f | %.4f" % [ask.get("price", 0.0), ask.get("amount", 0.0)]
                        label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2, 1.0))
                        container.add_child(label)

func _update_spread(bids: Array, asks: Array):
        if bids.size() > 0 and asks.size() > 0:
                var best_bid = bids[0].get("price", 0.0)
                var best_ask = asks[0].get("price", 0.0)
                var spread = best_ask - best_bid
                var label = $VBoxContainer/SpreadInfo/SpreadLabel
                if label:
                        label.text = "Spread: $%.2f (%.3f%%)" % [spread, (spread / best_ask) * 100]

func _on_price_updated(symbol: String, price: float):
        if symbol == current_symbol:
                _request_orderbook()

func _on_back_pressed():
        get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")
