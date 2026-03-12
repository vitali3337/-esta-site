const API_URL = "https://realinvest-api-production.up.railway.app";

async function loadListings(){

const res = await fetch(API_URL + "/listings");

const data = await res.json();

renderListings(data.listings);

}

function renderListings(listings){

const container = document.getElementById("listings");

if(!container) return;

container.innerHTML = "";

listings.forEach(l => {

const card = document.createElement("div");

card.className = "listing-card";

card.innerHTML = `
<img src="${l.image}">
<h3>${l.title}</h3>
<p>${l.city}</p>
<p>${l.price}$</p>
`;

container.appendChild(card);

});

}

loadListings();
